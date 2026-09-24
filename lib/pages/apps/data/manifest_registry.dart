import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/storage/paths.dart';
import 'catalog_context.dart' show kManifestsRoot;
import 'models/manifest.dart';
import '../../../services/logging.dart';

class ManifestRegistry extends ChangeNotifier {
  ManifestRegistry({required this.client});

  final FlipperClient client;

  final Map<String, AppManifest> _byUid = {};
  final Map<String, AppManifest> _byAlias = {};
  final Map<String, String> _md5 = {};

  bool _loading = false;
  bool get loading => _loading;

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
    notifyListeners();
    try {
      if (_byAlias.isEmpty) await _loadCache();
      if (token.isStale) return;

      final list = await client.storageList(
        ListRequest(path: kManifestsRoot, includeMd5: true),
        timeout: const Duration(seconds: 20),
        priority: FlipperRequestPriority.background,
      );
      if (token.isStale) return;

      final prevManifests = Map<String, AppManifest>.from(_byAlias);
      final prevMd5 = Map<String, String>.from(_md5);
      _byUid.clear();
      _byAlias.clear();
      _md5.clear();

      var reused = 0;
      var read = 0;
      for (final item in list.items) {
        for (final f in item.file) {
          if (f.type != File_FileType.FILE) continue;
          if (!f.name.endsWith('.fim')) continue;
          final alias = f.name.substring(0, f.name.length - 4);
          if (alias.isEmpty) continue;

          final md5 = f.md5sum;
          AppManifest? manifest;
          if (!force &&
              md5.isNotEmpty &&
              prevMd5[alias] == md5 &&
              prevManifests[alias] != null) {
            manifest = prevManifests[alias];
            reused++;
          } else {
            manifest = await _readManifest('$kManifestsRoot/${f.name}');
            if (token.isStale) return;
            read++;
          }
          if (manifest != null) {
            _index(alias, manifest);
            if (md5.isNotEmpty) _md5[alias] = md5;
          }
          notifyListeners();
        }
      }
      _loaded = true;
      LogService.info(
        '[Manifests] ${_byAlias.length} installed (reused $reused, read $read)',
      );
      await _saveCache();
    } catch (e) {
      // _loaded is not cleared here, so after one good refresh a later
      // failure leaves it true. The maps are cleared inside the try, so what
      // survives is the previous list if storageList threw and a partial one
      // if anything below it did. On a cold start with no cache it reads as
      // an ordinary empty catalogue.
      LogService.warn('[Manifests] refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _index(String alias, AppManifest manifest) {
    _byAlias[alias] = manifest;
    if (manifest.uid.isNotEmpty) _byUid[manifest.uid] = manifest;
  }

  void put(String alias, AppManifest manifest) {
    _index(alias, manifest);
    unawaited(_saveCache());
    notifyListeners();
  }

  void removeAlias(String alias) {
    final m = _byAlias.remove(alias);
    if (m != null && m.uid.isNotEmpty) _byUid.remove(m.uid);
    _md5.remove(alias);
    unawaited(_saveCache());
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

  Future<void> _loadCache() async {
    try {
      final name = await client.awaitName().timeout(const Duration(seconds: 5));
      final file = await installedCatalogFile(name);
      if (!await file.exists()) return;
      final body = await file.readAsString();
      if (body.trim().isEmpty) return;
      final data = jsonDecode(body) as Map<String, dynamic>;
      final items = data['manifests'] as List<dynamic>? ?? const [];
      for (final raw in items) {
        final e = raw as Map<String, dynamic>;
        final alias = (e['alias'] as String?)?.trim() ?? '';
        final path = (e['path'] as String?)?.trim() ?? '';
        if (alias.isEmpty || path.isEmpty) continue;
        _index(
          alias,
          AppManifest(
            uid: (e['uid'] as String?) ?? '',
            versionUid: (e['version_uid'] as String?) ?? '',
            fullName: (e['full_name'] as String?) ?? '',
            path: path,
            iconBase64: (e['icon_base64'] as String?) ?? '',
            sdkApi: (e['sdk_api'] as String?) ?? '',
            devCatalog: (e['dev_catalog'] as bool?) ?? false,
          ),
        );
        final md5 = (e['md5'] as String?) ?? '';
        if (md5.isNotEmpty) _md5[alias] = md5;
      }
    } catch (_) {}
  }

  Future<void> _saveCache() async {
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
          'version_uid': m.versionUid,
          'full_name': m.fullName,
          'path': m.path,
          'sdk_api': m.sdkApi,
          'icon_base64': m.iconBase64,
          'dev_catalog': m.devCatalog,
          if (_md5[e.key] != null) 'md5': _md5[e.key],
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
