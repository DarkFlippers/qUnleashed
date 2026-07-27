import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/repository/app.dart';
import 'apps_backend.dart' show kManifestsRoot;
import 'models/manifest.dart';

class ManifestRegistry extends ChangeNotifier {
  ManifestRegistry({required this.client});

  final FlipperClient client;

  final Map<String, AppManifest> _byUid = {};
  final Map<String, AppManifest> _byAlias = {};
  final Map<String, String> _md5 = {};

  bool _loading = false;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool get _isReady => client.isConnected && client.mode == FlipperMode.rpc;

  AppManifest? byUid(String uid) => uid.isEmpty ? null : _byUid[uid];
  AppManifest? byAlias(String alias) => alias.isEmpty ? null : _byAlias[alias];
  List<AppManifest> get all => List.unmodifiable(_byAlias.values);
  Set<String> get installedUids => _byUid.keys.toSet();

  Future<void> ensureFresh() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    if (!_isReady) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (_byAlias.isEmpty) await _loadCache();

      final list = await client.storageList(
        ListRequest(path: kManifestsRoot, includeMd5: true),
        timeout: const Duration(seconds: 20),
      );

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
      LogService.log(
        '[Manifests] ${_byAlias.length} installed (reused $reused, read $read)',
      );
      await _saveCache();
    } catch (e) {
      _error = e;
      LogService.log('[Manifests] refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _index(String alias, AppManifest manifest) {
    _byAlias[alias] = manifest;
    if (manifest.uid.isNotEmpty) _byUid[manifest.uid] = manifest;
  }

  void put(String alias, AppManifest manifest, {int? fimSize}) {
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
      LogService.log('[Manifests] read "$path" failed: $e');
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
    try {
      final name = await client.awaitName().timeout(const Duration(seconds: 5));
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
      LogService.log('[Manifests] cache save failed: $e');
    }
  }
}
