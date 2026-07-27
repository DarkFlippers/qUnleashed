import 'dart:async';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/repository/app.dart';
import '../icons/icon_resolver.dart';
import 'apps_backend.dart';
import 'catalog_api.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/installed_app.dart';

class DeviceSource extends ChangeNotifier {
  DeviceSource({
    required this.client,
    required this.api,
    required this.manifests,
    required this.engine,
    required this.backend,
  }) {
    manifests.addListener(notifyListeners);
  }

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final InstallEngine engine;
  final AppsBackend backend;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  final Map<String, ({int size, String folder})> _local = {};

  List<InstalledApp> get apps {
    final ids = <String>{
      for (final m in manifests.all)
        if (m.path.isNotEmpty) _aliasFromPath(m.path),
      ..._local.keys,
    };
    final out = <InstalledApp>[];
    for (final alias in ids) {
      if (alias.isEmpty) continue;
      final m = manifests.byAlias(alias);
      final local = _local[alias];
      final folder = local?.folder ??
          (m != null && m.path.isNotEmpty ? _folderFromPath(m.path) : '');
      final devicePath = m != null && m.path.isNotEmpty
          ? m.path
          : '$kAppsRoot/$folder/$alias.fap';
      out.add(InstalledApp(
        alias: alias,
        path: devicePath,
        folder: folder,
        size: local?.size ?? 0,
        md5: '',
        manifest: m,
      ));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(out);
  }

  bool _syncing = false;
  bool get scanning => _syncing;

  int _syncTotal = 0;
  int _syncDone = 0;
  String? _syncingItem;
  String? get scanningFolder => _syncingItem;
  double get scanProgress => _syncTotal == 0 ? 0 : _syncDone / _syncTotal;

  Object? _error;
  Object? get error => _error;

  List<String> get groups {
    final set = <String>{for (final a in apps) a.folder};
    return set.toList()..sort();
  }

  String _aliasFromPath(String path) {
    final base = path.substring(path.lastIndexOf('/') + 1);
    return base.endsWith('.fap') ? base.substring(0, base.length - 4) : base;
  }

  String _folderFromPath(String path) {
    final parts = path.split('/')..removeWhere((e) => e.isEmpty);
    final idx = parts.indexOf('apps');
    if (idx >= 0 && parts.length > idx + 2) return parts[idx + 1];
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  Future<void> prime() async {
    await _loadLocalApps();
    notifyListeners();
    await manifests.ensureFresh();
    _warmManifestIcons();
    notifyListeners();
  }

  Future<void> _loadLocalApps() async {
    final map = <String, ({int size, String folder})>{};
    try {
      final name = await _deviceName();
      if (name != null) {
        final dir = await appsBackupDirectory(name);
        if (await dir.exists()) {
          final sep = io.Platform.pathSeparator;
          await for (final e in dir.list(recursive: true, followLinks: false)) {
            if (e is! io.File) continue;
            final base = e.path.substring(e.path.lastIndexOf(sep) + 1);
            if (!base.endsWith('.fap')) continue;
            final alias = base.substring(0, base.length - 4);
            if (alias.isEmpty) continue;
            final parent = e.parent.path;
            final folder = parent.substring(parent.lastIndexOf(sep) + 1);
            int size = 0;
            try {
              size = await e.length();
            } catch (_) {}
            map[alias] = (size: size, folder: folder);
          }
        }
      }
    } catch (_) {}
    _local
      ..clear()
      ..addAll(map);
  }

  Future<void> scan() async {
    if (!isReady || _syncing) return;
    _syncing = true;
    _error = null;
    _syncDone = 0;
    _syncTotal = 0;
    _syncingItem = null;
    notifyListeners();
    try {
      await manifests.refresh();
      final deviceApps = await _walkDevice();
      _syncTotal = deviceApps.length;
      notifyListeners();

      final name = await _deviceName();
      if (name == null) return;
      final dir = await appsBackupDirectory(name);

      for (final d in deviceApps) {
        if (!isReady) break;
        _syncingItem = d.alias;
        notifyListeners();
        final local = io.File(pathJoin(
            [dir.path, sanitizePathSegment(d.folder), '${d.alias}.fap']));
        final needs = !await local.exists() ||
            !await _localMatchesRemote(local, d.md5, d.devicePath);
        if (needs) {
          try {
            final bytes = await client.storageReadChunked(
              d.devicePath,
              timeout: const Duration(seconds: 60),
              priority: FlipperRequestPriority.background,
            );
            if (bytes.isNotEmpty) {
              await local.parent.create(recursive: true);
              await local.writeAsBytes(bytes, flush: true);
              unawaited(IconResolver.instance.ensureFromFap(d.alias, bytes));
            }
          } catch (e) {
            LogService.log('[DeviceSource] download "${d.alias}" failed: $e');
          }
        }
        _syncDone++;
        await _loadLocalApps();
        notifyListeners();
      }
      _warmManifestIcons();
      LogService.log('[DeviceSource] sync: ${apps.length} apps');
    } catch (e) {
      _error = e;
      LogService.log('[DeviceSource] sync failed: $e');
    } finally {
      _syncing = false;
      _syncingItem = null;
      notifyListeners();
    }
  }

  Future<
      List<
          ({
            String alias,
            String folder,
            String devicePath,
            String md5,
            int size
          })>> _walkDevice() async {
    final root = await client.storageList(
      ListRequest(path: kAppsRoot),
      timeout: const Duration(seconds: 20),
    );
    final folders = <String>[
      for (final item in root.items)
        for (final f in item.file)
          if (f.type == File_FileType.DIR && f.name.isNotEmpty) f.name,
    ];
    final out = <({
      String alias,
      String folder,
      String devicePath,
      String md5,
      int size
    })>[];
    for (final folder in folders) {
      if (!isReady) break;
      _syncingItem = folder;
      notifyListeners();
      final list = await client.storageList(
        ListRequest(path: '$kAppsRoot/$folder', includeMd5: true),
        timeout: const Duration(seconds: 20),
      );
      for (final item in list.items) {
        for (final f in item.file) {
          if (f.type != File_FileType.FILE) continue;
          if (!f.name.endsWith('.fap')) continue;
          final alias = f.name.substring(0, f.name.length - 4);
          if (alias.isEmpty) continue;
          out.add((
            alias: alias,
            folder: folder,
            devicePath: '$kAppsRoot/$folder/${f.name}',
            md5: f.md5sum,
            size: f.size,
          ));
        }
      }
    }
    return out;
  }

  Future<bool> _localMatchesRemote(
      io.File local, String remoteMd5, String devicePath) async {
    try {
      final localMd5 =
          md5.convert(await local.readAsBytes()).toString().toLowerCase();
      var wanted = remoteMd5.trim().toLowerCase();
      if (wanted.isEmpty) {
        final batch = await client.storageMd5sum(
          Md5sumRequest(path: devicePath),
          timeout: const Duration(seconds: 15),
        );
        wanted = (batch.items.isNotEmpty ? batch.items.first.md5sum : '')
            .trim()
            .toLowerCase();
      }
      return wanted.isNotEmpty && wanted == localMd5;
    } catch (e) {
      LogService.log('[DeviceSource] md5 check $devicePath failed: $e');
      return false;
    }
  }

  Future<void> launch(InstalledApp app) => engine.launchPath(app.path);

  Future<bool> restore(InstalledApp app) async {
    final name = await _deviceName();
    if (name == null) return false;
    final dir = await appsBackupDirectory(name);
    final file = io.File(pathJoin(
        [dir.path, sanitizePathSegment(app.folder), '${app.alias}.fap']));
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    return engine.restore(
      alias: app.alias,
      fapPath: app.path,
      fapBytes: bytes,
      manifest: app.manifest,
    );
  }

  Future<void> deleteLocal(InstalledApp app) async {
    try {
      final name = await _deviceName();
      if (name == null) return;
      final dir = await appsBackupDirectory(name);
      final file = io.File(pathJoin(
          [dir.path, sanitizePathSegment(app.folder), '${app.alias}.fap']));
      if (await file.exists()) await file.delete();
    } catch (_) {}
    await _loadLocalApps();
    notifyListeners();
  }

  Future<void> uninstallFromDevice(InstalledApp app) async {
    await engine.deleteInstalled(alias: app.alias, fapPath: app.path);
    await deleteLocal(app);
  }

  void _warmManifestIcons() {
    for (final app in apps) {
      final m = app.manifest;
      if (m != null && m.iconBase64.isNotEmpty) {
        unawaited(IconResolver.instance.ensureFromManifest(app.alias, m));
      }
    }
  }

  Future<String?> _deviceName() async {
    try {
      return await client.awaitName().timeout(const Duration(seconds: 5));
    } catch (_) {
      return client.getName();
    }
  }

  void handleDisconnect() => notifyListeners();

  void handleDeviceChange() {
    _local.clear();
    _syncDone = 0;
    _syncTotal = 0;
    notifyListeners();
    unawaited(_refreshLocal());
  }

  Future<void> _refreshLocal() async {
    await _loadLocalApps();
    notifyListeners();
  }
}
