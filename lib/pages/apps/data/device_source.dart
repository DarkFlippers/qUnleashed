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

  /// Counts device switches, so that work started against one Flipper cannot
  /// file its result under another.
  ///
  /// A scan, a download or an install runs for as long as it runs, and the
  /// maps above describe whichever device is attached now - so every pass
  /// takes this number at its start and, after each await, drops what it was
  /// about to write if the number has moved. A dropped link is a different
  /// matter that [isReady] already covers: a device swapped on a live link
  /// leaves that reading true throughout.
  int _generation = 0;
  Future<void> _localPass = Future<void>.value();

  bool _stale(int gen) => gen != _generation;

  /// Queues the passes over [_local] and [_parsed] behind one another.
  ///
  /// Two at once means one rebuilding a map while the other is iterating it,
  /// which throws. This is not what [_priming] does - that one only keeps a
  /// second `prime` from repeating the first; these passes also arrive from a
  /// scan, from a delete and from a device switch, and none of them know about
  /// each other.
  Future<void> _serial(Future<void> Function() body) {
    final pass = _localPass.then((_) => body());
    _localPass = pass.then((_) {}, onError: (_) {});
    return pass;
  }

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

  Future<void>? _priming;

  Future<void> prime() =>
      _priming ??= _prime().whenComplete(() => _priming = null);

  Future<void> _prime() async {
    final gen = _generation;
    await _loadLocalApps();
    if (_stale(gen)) return;
    notifyListeners();
    await manifests.ensureFresh();
    if (_stale(gen)) return;
    _warmManifestIcons();
    notifyListeners();
    await _parseLocalFaps();
  }

  Future<void> _loadLocalApps() => _serial(_readLocalMirror);

  Future<void> _readLocalMirror() async {
    final gen = _generation;
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
    if (_stale(gen)) return;
    _local
      ..clear()
      ..addAll(map);
  }

  /// Reads every local `.fap` copy that changed since the last pass and keeps
  /// its parsed manifest, sections and assets around for the manager UI.
  Future<void> _parseLocalFaps() => _serial(_parsePendingFaps);

  Future<void> _parsePendingFaps() async {
    final gen = _generation;
    var changed = false;

    for (final alias in _local.keys.toList()) {
      final entry = _local[alias];
      if (entry == null) continue;
      final stamp = Object.hash(entry.size, entry.stamp);
      if (_parsed.containsKey(alias) && _parsedStamp[alias] == stamp) continue;
      FapInfo? info;
      try {
        info = FapInfo.parse(await io.File(entry.path).readAsBytes());
      } catch (e) {
        // One per app in the parse loop, and fap_facts renders an explicit
        // "not a valid application file" for the null this leaves.
        LogService.info('[DeviceSource] parse "$alias" failed: $e');
        info = null;
      }
      if (_stale(gen)) return;
      // Records compare by value, which is what carries this check: a table
      // rebuilt from the same files still matches, while a copy replaced while
      // its bytes were being read does not. Turning the entry into a class
      // would leave identity equality here, and every parse would be dropped
      // without a word.
      if (_local[alias] != entry) continue;
      _parsed[alias] = info;
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
    final gen = _generation;
    _syncing = true;
    _syncDone = 0;
    _syncTotal = 0;
    _syncingItem = null;
    notifyListeners();
    try {
      await manifests.refresh();
      final walk = await _walkDevice();
      if (_stale(gen)) return;
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
        if (!isReady || _stale(gen)) break;
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
            if (bytes.isNotEmpty && !_stale(gen)) {
              await local.parent.create(recursive: true);
              await local.writeAsBytes(bytes, flush: true);
              unawaited(IconResolver.instance.ensureFromFap(d.alias, bytes));
            }
          } catch (e) {
            // One per app in the scan loop; the alias in the text stops
            // repeats collapsing, so a failed scan of a full device would
            // write an entry per app.
            LogService.info('[DeviceSource] download "${d.alias}" failed: $e');
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
      LogService.info('[DeviceSource] sync: ${apps.length} apps');
    } catch (e) {
      // The whole sync, once per user action. Nothing is set for the UI to
      // read - the list simply stops where it got to.
      LogService.warn('[DeviceSource] sync failed: $e');
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
      // One per app, and false is the safe answer: it re-downloads rather
      // than trusting a file it could not check.
      LogService.info('[DeviceSource] md5 check $devicePath failed: $e');
      return false;
    }
  }

  Future<void> launch(InstalledApp app) => engine.launchPath(app.path);

  Future<bool> restore(InstalledApp app) async {
    final gen = _generation;
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
    if (ok && !_stale(gen)) {
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
    final gen = _generation;
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
      // Once per install, not per app - adoptInstalled is the onInstalled
      // callback. And the entry below is written regardless, with an empty
      // localPath, so the manager shows a backup that is not there until the
      // user taps Restore and is told there is none.
      LogService.warn('[DeviceSource] local copy of "$alias" failed: $e');
    }
    if (_stale(gen)) return;
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
    final gen = _generation;
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
    if (_stale(gen)) return;
    await _loadLocalApps();
    await _parseLocalFaps();
    notifyListeners();
  }

  Future<void> uninstallFromDevice(InstalledApp app) async {
    final gen = _generation;
    await engine.deleteInstalled(alias: app.alias, fapPath: app.path);
    if (_stale(gen)) return;
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
    _generation++;
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
