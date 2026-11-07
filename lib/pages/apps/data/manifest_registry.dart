import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/guarded.dart';
import '../../../services/storage/paths.dart';
import 'catalog_context.dart' show kManifestsRoot;
import 'models/manifest.dart';
import '../../../services/logging.dart';

class ManifestRegistry extends ChangeNotifier {
  ManifestRegistry({
    required this.client,
    this.root = kManifestsRoot,
    this.cached = true,
  });

  final FlipperClient client;
  final String root;
  final bool cached;

  final Map<String, AppManifest> _byUid = {};
  final Map<String, AppManifest> _byAlias = {};
  final Map<String, String> _md5 = {};

  bool _loading = false;
  bool get loading => _loading;

  bool _failed = false;

  /// Whether the last read of what is installed came back short.
  ///
  /// Without it an empty list means "this Flipper has no apps" and "we could
  /// not read them" alike, and the manager renders the same screen for both.
  /// #112.
  bool get failed => _failed;

  bool _loaded = false;

  bool get _isReady => client.isRpcReady;

  AppManifest? byUid(String uid) => uid.isEmpty ? null : _byUid[uid];
  AppManifest? byAlias(String alias) => alias.isEmpty ? null : _byAlias[alias];
  List<AppManifest> get all => List.unmodifiable(_byAlias.values);

  Future<void> ensureFresh() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  /// Reads the manifests off the device as one background task, so a Flipper
  /// swapped mid-refresh cannot answer the rest of it.
  Future<void> refresh({bool force = false}) {
    if (_loading) return Future.value();
    if (!_isReady) return Future.value();
    return client.runTask(
      FlipperRequestPriority.background,
      () => _refresh(force: force),
    );
  }

  Future<void> _refresh({required bool force}) async {
    final token = client.deviceToken;
    _loading = true;
    _changed.clear();
    notifyListeners();
    try {
      if (_byAlias.isEmpty) await _loadCache();
      if (token.isStale) return;

      FlipperRpcBatch<ListResponse>? list;
      try {
        list = await client.storageList(
          ListRequest(path: root, includeMd5: true),
          timeout: const Duration(seconds: 20),
          priority: FlipperRequestPriority.background,
        );
      } on FlipperRpcStorageNotExistException {
        list = null;
      }
      if (token.isStale) return;

      // The new list is built beside the one shown, which stays whole until
      // this one is. Cleared first, it left every app not yet read again
      // looking not installed for as long as the reads over BLE took, and
      // the catalog offered to install apps that were on the Flipper. What
      // is read is still shown as it comes, so a first read fills the
      // screen as before; only an app gone from the Flipper waits for the
      // end to go.
      final byAlias = <String, AppManifest>{};
      final byUid = <String, AppManifest>{};
      final md5s = <String, String>{};

      var reused = 0;
      var read = 0;
      for (final item in list?.items ?? const <ListResponse>[]) {
        for (final f in item.file) {
          if (f.type != File_FileType.FILE) continue;
          if (!f.name.endsWith('.fim')) continue;
          final alias = f.name.substring(0, f.name.length - 4);
          if (alias.isEmpty) continue;

          final md5 = f.md5sum;
          final known = _byAlias[alias];
          AppManifest? manifest;
          if (!force && md5.isNotEmpty && _md5[alias] == md5 && known != null) {
            manifest = known;
            reused++;
          } else {
            manifest = await _readManifest('$root/${f.name}');
            if (token.isStale) return;
            read++;
          }
          if (manifest != null) {
            _indexInto(byAlias, byUid, alias, manifest);
            if (md5.isNotEmpty) md5s[alias] = md5;
            _index(alias, manifest);
          }
          notifyListeners();
        }
      }
      // An install or a delete that ended while the list was read is newer
      // than the list. Its file is read again on the next refresh.
      for (final MapEntry(key: alias, value: manifest) in _changed.entries) {
        md5s.remove(alias);
        if (manifest != null) {
          _indexInto(byAlias, byUid, alias, manifest);
        } else {
          final gone = byAlias.remove(alias);
          if (gone != null && byUid[gone.uid] == gone) byUid.remove(gone.uid);
        }
      }
      _byAlias
        ..clear()
        ..addAll(byAlias);
      _byUid
        ..clear()
        ..addAll(byUid);
      _md5
        ..clear()
        ..addAll(md5s);
      _loaded = true;
      _failed = false;
      LogService.info(
        '[Manifests] ${_byAlias.length} installed (reused $reused, read $read)',
      );
      await _saveCache();
    } catch (e) {
      // _loaded is not cleared here, so after one good refresh a later
      // failure leaves it true. Nothing shown is taken away before the new
      // list is whole, so what survives is the previous list, with what was
      // read before the failure added to it. On a cold start with no cache it
      // read as an ordinary empty catalogue - which is what [failed] is for.
      _failed = true;
      LogService.warn('[Manifests] refresh failed: $e');
    } finally {
      _loading = false;
      _changed.clear();
      notifyListeners();
    }
  }

  void _index(String alias, AppManifest manifest) =>
      _indexInto(_byAlias, _byUid, alias, manifest);

  static void _indexInto(
    Map<String, AppManifest> byAlias,
    Map<String, AppManifest> byUid,
    String alias,
    AppManifest manifest,
  ) {
    byAlias[alias] = manifest;
    if (manifest.uid.isNotEmpty) byUid[manifest.uid] = manifest;
  }

  /// What [put] and [removeAlias] did while a refresh was reading the list,
  /// alias -> the manifest put, or null for one removed: applied to the new
  /// list before it takes the place of the one shown.
  final Map<String, AppManifest?> _changed = {};

  void put(String alias, AppManifest manifest) {
    _index(alias, manifest);
    if (_loading) _changed[alias] = manifest;
    unawaited(guarded('[Manifests] save cache', _saveCache));
    notifyListeners();
  }

  void removeAlias(String alias) {
    final m = _byAlias.remove(alias);
    if (m != null && m.uid.isNotEmpty) _byUid.remove(m.uid);
    _md5.remove(alias);
    if (_loading) _changed[alias] = null;
    unawaited(guarded('[Manifests] save cache', _saveCache));
    notifyListeners();
  }

  void handleDisconnect() {
    _loaded = false;
    notifyListeners();
  }

  void handleDeviceChange() {
    _byUid.clear();
    _byAlias.clear();
    _md5.clear();
    _loaded = false;
    notifyListeners();
  }

  Future<AppManifest?> _readManifest(String path) async {
    try {
      final bytes = await client.storageReadChunked(
        path,
        timeout: const Duration(seconds: 20),
      );
      if (bytes.isEmpty) return null;
      return AppManifest.tryParse(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      // One per manifest in the refresh loop, with the path in the text, so
      // a disconnect mid-refresh would write an entry per installed app.
      LogService.info('[Manifests] read "$path" failed: $e');
      return null;
    }
  }

  /// Reads the on-disk catalogue, for a test that wants that path alone.
  ///
  /// `_refresh` calls it first and then goes to the device; the cache is what
  /// fills the apps screen before the Flipper has answered.
  @visibleForTesting
  Future<void> readCacheFile() => _loadCache();

  /// Loads the catalogue written on the last refresh.
  ///
  /// Entry by entry, so one app whose record changed shape costs itself and
  /// not the list. It used to be a single `catch (_) {}` around the whole
  /// loop, which meant a throw on the fifth of fifty left four apps indexed,
  /// the rest missing, and nothing said anywhere - #138.
  Future<void> _loadCache() async {
    if (!cached) return;
    final String body;
    try {
      final name = await client.awaitName().timeout(const Duration(seconds: 5));
      final file = await installedCatalogFile(name);
      if (!await file.exists()) return;
      body = await file.readAsString();
    } catch (e) {
      // The whole catalogue rather than one entry: no name, or a file that
      // will not open. The refresh behind this reads the device itself, so
      // what is lost is the head start, not the list - but it is a loss, and
      // it used to happen in silence.
      LogService.warn('[Manifests] cached catalogue unreadable: $e');
      return;
    }
    if (body.trim().isEmpty) return;

    final List<dynamic> items;
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      items = data['manifests'] as List<dynamic>? ?? const [];
    } catch (e) {
      LogService.warn('[Manifests] cached catalogue is not one: $e');
      return;
    }

    var dropped = 0;
    for (final raw in items) {
      if (!_indexCached(raw)) dropped++;
    }
    if (dropped > 0) {
      // Once for the batch. A catalogue whose shape has changed drops every
      // entry, and one line per installed app is a log nobody reads.
      LogService.warn(
        '[Manifests] dropped $dropped of ${items.length} cached entries',
      );
    }
  }

  /// Indexes one cached entry. False when it could not be read.
  ///
  /// Nothing here casts: the file is written by an older build of this app as
  /// much as by this one, and a field that changed type is exactly the case
  /// that used to take the rest of the list with it.
  bool _indexCached(Object? raw) {
    if (raw is! Map<String, dynamic>) return false;
    final alias = _text(raw['alias']);
    final path = _text(raw['path']);
    if (alias == null || path == null) return false;

    _index(
      alias,
      AppManifest(
        uid: _text(raw['uid']) ?? '',
        versionUid: _text(raw['version_uid']),
        fullName: _text(raw['full_name']),
        path: path,
        iconBase64: _text(raw['icon_base64']),
        sdkApi: _text(raw['sdk_api']),
        devCatalog: raw['dev_catalog'] == true,
        appId: _text(raw['app_id']),
        appVersion: _text(raw['app_version']),
        family: ManifestFamily.byCode(_text(raw['family'])),
        catalog: _text(raw['catalog']),
      ),
    );
    final md5 = _text(raw['md5']);
    if (md5 != null) _md5[alias] = md5;
    return true;
  }

  /// A string field that is a string and is not blank, or null.
  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _saveCache() async {
    if (!cached) return;
    final token = client.deviceToken;
    try {
      final name = await client.awaitName().timeout(const Duration(seconds: 5));
      // The name resolves to whichever Flipper is in scope when it answers, so
      // without this a list belonging to the previous one would be written into
      // the new one's catalogue file and read back as its own on next launch.
      if (token.isStale) return;
      final manifests = _byAlias.entries.map((e) {
        final m = e.value;
        return {
          'alias': e.key,
          'uid': m.uid,
          'version_uid': ?m.versionUid,
          'full_name': ?m.fullName,
          'path': m.path,
          'sdk_api': ?m.sdkApi,
          'icon_base64': ?m.iconBase64,
          'dev_catalog': m.devCatalog,
          'app_id': ?m.appId,
          'app_version': ?m.appVersion,
          'family': ?m.family?.code,
          'catalog': ?m.catalog,
          'md5': ?_md5[e.key],
        };
      }).toList();
      final file = await installedCatalogFile(name);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'count': manifests.length, 'manifests': manifests}),
        flush: true,
      );
    } catch (e) {
      // Costs a slow start rather than correctness - the next launch reads
      // every manifest off the device again instead of the cache - but nothing
      // else records that it happened.
      LogService.warn('[Manifests] cache save failed: $e');
    }
  }
}
