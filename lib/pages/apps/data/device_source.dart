import 'dart:async';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../components/codec/fap/info.dart';
import '../../../components/path.dart';
import '../../../services/progress_throttle.dart';
import '../../../services/storage/paths.dart';
import '../icons/icon_resolver.dart';
import 'catalog_context.dart';
import 'catalog_api.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/installed_app.dart';
import '../../../services/logging.dart';

/// One `.fap` as the device reports it.
typedef _DeviceFap = ({
  String alias,
  String folder,
  String devicePath,
  String md5,
  int size,
});

class DeviceSource extends ChangeNotifier {
  DeviceSource({
    required this.client,
    required this.api,
    required this.manifests,
    required this.engine,
  }) {
    manifests.addListener(notifyListeners);
  }

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final InstallEngine engine;

  bool get isReady => client.isRpcReady;

  /// Overrides where mirrored copies of installed apps live.
  ///
  /// Tests only. The real path is derived from the user's documents directory
  /// through platform environment variables, which a test process cannot
  /// change - so without this a test either reads and writes the developer's
  /// real Devices folder, or, where no device has ever been remembered, skips
  /// the mirroring half of a scan entirely. Both make what is covered depend
  /// on the machine.
  @visibleForTesting
  static Future<io.Directory> Function(String deviceName)? backupDirectory;

  Future<io.Directory> _backupDir(String deviceName) =>
      (backupDirectory ?? appsBackupDirectory)(deviceName);

  final Map<String, ({int size, String folder, String path, int stamp})>
  _local = {};

  /// Aliases whose `.fap` the last complete device walk found.
  ///
  /// Null until one completes. That distinction is the whole point: a device
  /// nobody has scanned, or one that disconnected mid-walk, must not read as a
  /// device with nothing installed - only a finished walk can prove an app is
  /// gone.
  Set<String>? _deviceAliases;

  final Map<String, FapInfo?> _parsed = {};
  final Map<String, int> _parsedStamp = {};

  FapInfo? infoFor(String alias) => _parsed[alias];

  List<InstalledApp> get apps {
    final ids = <String>{
      for (final m in manifests.all)
        if (m.path.isNotEmpty) aliasFromFapPath(m.path),
      ..._local.keys,
    };
    final out = <InstalledApp>[];
    for (final alias in ids) {
      if (alias.isEmpty) continue;
      final m = manifests.byAlias(alias);
      final local = _local[alias];
      final onDevice = _deviceAliases?.contains(alias);
      final folder =
          local?.folder ??
          (m != null && m.path.isNotEmpty ? _folderFromPath(m.path) : '');
      final devicePath = m != null && m.path.isNotEmpty
          ? m.path
          : '$kAppsRoot/$folder/$alias.fap';
      out.add(
        InstalledApp(
          alias: alias,
          path: devicePath,
          folder: folder,
          size: local?.size ?? 0,
          manifest: m,
          fap: _parsed[alias],
          fapChecked: _parsed.containsKey(alias),
          onDevice: onDevice,
        ),
      );
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

  bool _downloading = false;
  double _fileProgress = 0;
  final ProgressThrottle _progressThrottle = ProgressThrottle();

  double? get fileProgress => _downloading ? _fileProgress : null;

  String _folderFromPath(String path) {
    final parts = path.split('/')..removeWhere((e) => e.isEmpty);
    final idx = parts.indexOf('apps');
    if (idx >= 0 && parts.length > idx + 2) return parts[idx + 1];
    // Directly inside the apps root: no folder, rather than the root's own
    // name. The mirror stores such a copy at its own root, so answering
    // "apps" here would send restore and delete to a path that never exists.
    if (idx >= 0 && parts.length == idx + 2) return '';
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  Future<void> prime() async {
    await _loadLocalApps();
    notifyListeners();
    await manifests.ensureFresh();
    _warmManifestIcons();
    notifyListeners();
    await _parseLocalFaps();
  }

  Future<void> _loadLocalApps() async {
    final map = <String, ({int size, String folder, String path, int stamp})>{};
    try {
      final name = await _deviceName();
      if (name != null) {
        final dir = await _backupDir(name);
        if (await dir.exists()) {
          final sep = io.Platform.pathSeparator;
          await for (final e in dir.list(recursive: true, followLinks: false)) {
            if (e is! io.File) continue;
            final base = e.path.substring(e.path.lastIndexOf(sep) + 1);
            if (!base.endsWith('.fap')) continue;
            final alias = base.substring(0, base.length - 4);
            if (alias.isEmpty) continue;
            final parent = e.parent.path;
            // A copy of an app that lives in the apps root sits in the mirror
            // root, where the parent directory is the mirror itself - reading
            // its name as the folder would send restore and delete looking in
            // a directory that does not exist.
            final folder = parent == dir.path
                ? ''
                : parent.substring(parent.lastIndexOf(sep) + 1);
            int size = 0;
            int stamp = 0;
            try {
              final stat = await e.stat();
              size = stat.size;
              stamp = stat.modified.millisecondsSinceEpoch;
            } catch (_) {}
            map[alias] = (
              size: size,
              folder: folder,
              path: e.path,
              stamp: stamp,
            );
          }
        }
      }
    } catch (_) {}
    _local
      ..clear()
      ..addAll(map);
  }

  /// Reads every local `.fap` copy that changed since the last pass and keeps
  /// its parsed manifest, sections and assets around for the manager UI.
  Future<void> _parseLocalFaps() async {
    var changed = false;

    for (final entry in _local.entries) {
      final alias = entry.key;
      final stamp = Object.hash(entry.value.size, entry.value.stamp);
      if (_parsed.containsKey(alias) && _parsedStamp[alias] == stamp) continue;
      try {
        final bytes = await io.File(entry.value.path).readAsBytes();
        _parsed[alias] = FapInfo.parse(bytes);
      } catch (e) {
        LogService.log('[DeviceSource] parse "$alias" failed: $e');
        _parsed[alias] = null;
      }
      _parsedStamp[alias] = stamp;
      changed = true;
    }

    for (final alias in _parsed.keys.toList()) {
      if (_local.containsKey(alias)) continue;
      _parsed.remove(alias);
      _parsedStamp.remove(alias);
      changed = true;
    }

    if (changed) notifyListeners();
  }

  Future<void> scan() async {
    if (!isReady || _syncing) return;
    _syncing = true;
    _syncDone = 0;
    _syncTotal = 0;
    _syncingItem = null;
    notifyListeners();
    try {
      await manifests.refresh();
      final walk = await _walkDevice();
      final deviceApps = walk.apps;
      // Only a complete walk proves absence. A partial one - a disconnect
      // mid-scan - must leave the previous answer alone rather than report an
      // empty device.
      if (walk.complete) {
        _deviceAliases = {for (final d in deviceApps) d.alias};
      }
      _syncTotal = deviceApps.length;
      notifyListeners();

      final name = await _deviceName();
      if (name == null) return;
      final dir = await _backupDir(name);

      for (final d in deviceApps) {
        if (!isReady) break;
        _syncingItem = d.alias;
        notifyListeners();
        final local = io.File(
          pathJoin([dir.path, sanitizePathSegment(d.folder), '${d.alias}.fap']),
        );
        final needs =
            !await local.exists() ||
            !await _localMatchesRemote(local, d.md5, d.devicePath);
        if (needs) {
          try {
            _downloading = true;
            _fileProgress = 0;
            _progressThrottle.reset();
            notifyListeners();
            final bytes = await client.storageReadChunked(
              d.devicePath,
              expectedSize: d.size,
              onProgress: (p) {
                _fileProgress = p;
                if (_progressThrottle.shouldEmit(p)) notifyListeners();
              },
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
          } finally {
            _downloading = false;
            _fileProgress = 0;
          }
        }
        _syncDone++;
        await _loadLocalApps();
        await _parseLocalFaps();
        notifyListeners();
      }
      _warmManifestIcons();
      LogService.log('[DeviceSource] sync: ${apps.length} apps');
    } catch (e) {
      LogService.log('[DeviceSource] sync failed: $e');
    } finally {
      _syncing = false;
      _syncingItem = null;
      notifyListeners();
    }
  }

  Future<({List<_DeviceFap> apps, bool complete})> _walkDevice() async {
    final out = <_DeviceFap>[];
    var complete = true;

    void collect(FlipperRpcBatch<ListResponse> listing, String folder) {
      final dir = folder.isEmpty ? kAppsRoot : '$kAppsRoot/$folder';
      for (final item in listing.items) {
        for (final f in item.file) {
          if (f.type != File_FileType.FILE) continue;
          if (!f.name.endsWith('.fap')) continue;
          final alias = aliasFromFapPath(f.name);
          if (alias.isEmpty) continue;
          out.add((
            alias: alias,
            folder: folder,
            devicePath: '$dir/${f.name}',
            md5: f.md5sum,
            size: f.size,
          ));
        }
      }
    }

    final root = await client.storageList(
      ListRequest(path: kAppsRoot),
      timeout: const Duration(seconds: 20),
    );
    // Apps normally live one folder deep, but a .fap sitting directly in the
    // apps root is installed too, and overlooking it would let the
    // completeness check call it absent.
    collect(root, '');

    final folders = <String>[
      for (final item in root.items)
        for (final f in item.file)
          if (f.type == File_FileType.DIR && f.name.isNotEmpty) f.name,
    ];
    // One level only, which is the layout the firmware's app loader expects.
    for (final folder in folders) {
      if (!isReady) {
        // Disconnected part-way: what was collected is still worth syncing,
        // but it is no longer evidence that anything is absent.
        complete = false;
        break;
      }
      _syncingItem = folder;
      notifyListeners();
      collect(
        await client.storageList(
          ListRequest(path: '$kAppsRoot/$folder'),
          timeout: const Duration(seconds: 20),
        ),
        folder,
      );
    }
    return (apps: out, complete: complete);
  }

  Future<bool> _localMatchesRemote(
    io.File local,
    String remoteMd5,
    String devicePath,
  ) async {
    try {
      final localMd5 = md5
          .convert(await local.readAsBytes())
          .toString()
          .toLowerCase();
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
    final dir = await _backupDir(name);
    final file = io.File(
      pathJoin([dir.path, sanitizePathSegment(app.folder), '${app.alias}.fap']),
    );
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final ok = await engine.restore(
      alias: app.alias,
      fapPath: app.path,
      fapBytes: bytes,
      manifest: app.manifest,
    );
    // Otherwise the app the user just put back keeps rendering as missing,
    // with no way out of that state but another full scan.
    if (ok) {
      _deviceAliases?.add(app.alias);
      notifyListeners();
    }
    return ok;
  }

  Future<void> adoptInstalled({
    required String alias,
    required String devicePath,
    required List<int> fapBytes,
  }) async {
    if (alias.isEmpty) return;
    final folder = _folderFromPath(devicePath);
    var localPath = '';
    try {
      final name = await _deviceName();
      if (name != null) {
        final dir = await _backupDir(name);
        final file = io.File(
          pathJoin([dir.path, sanitizePathSegment(folder), '$alias.fap']),
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(fapBytes, flush: true);
        localPath = file.path;
      }
    } catch (e) {
      LogService.log('[DeviceSource] local copy of "$alias" failed: $e');
    }
    _local[alias] = (
      size: fapBytes.length,
      folder: folder,
      path: localPath,
      stamp: 0,
    );
    _parsed[alias] = FapInfo.parse(Uint8List.fromList(fapBytes));
    _parsedStamp.remove(alias);
    // The app is on the device now. Without this the set still describes the
    // walk that ran before the install, so an app the user has just installed
    // renders as one that is missing from the device.
    _deviceAliases?.add(alias);
    notifyListeners();
  }

  Future<void> deleteLocal(InstalledApp app) async {
    try {
      final name = await _deviceName();
      if (name == null) return;
      final dir = await _backupDir(name);
      final file = io.File(
        pathJoin([
          dir.path,
          sanitizePathSegment(app.folder),
          '${app.alias}.fap',
        ]),
      );
      if (await file.exists()) await file.delete();
    } catch (_) {}
    await _loadLocalApps();
    await _parseLocalFaps();
    notifyListeners();
  }

  Future<void> uninstallFromDevice(InstalledApp app) async {
    await engine.deleteInstalled(alias: app.alias, fapPath: app.path);
    _deviceAliases?.remove(app.alias);
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
    if (isReady) {
      try {
        return await client.awaitName().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    final live = client.getName();
    if (live != null && live.isNotEmpty) return live;
    return lastDeviceName();
  }

  void handleDisconnect() => notifyListeners();

  void handleConnect() {
    // Apps can be added or removed while disconnected - through a card reader,
    // or the Flipper itself - so what the last walk saw is no longer evidence.
    _deviceAliases = null;
    notifyListeners();
  }

  void handleDeviceChange() {
    _local.clear();
    _parsed.clear();
    _parsedStamp.clear();
    // Device-scoped like the three above: this set describes one device's
    // storage, and this is a different device.
    _deviceAliases = null;
    _syncDone = 0;
    _syncTotal = 0;
    notifyListeners();
    unawaited(_refreshLocal());
  }

  Future<void> _refreshLocal() async {
    await _loadLocalApps();
    notifyListeners();
    await _parseLocalFaps();
  }
}
