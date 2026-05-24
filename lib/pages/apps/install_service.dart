import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../storage/app_documents.dart';
import 'catalog_api.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'models/detail.dart';
import 'models/manifest.dart';

const String kAppsRoot = '/ext/apps';
const String kManifestsRoot = '/ext/apps_manifests';
const String kTempRoot = '/ext/.tmp/qunleashed';
const String kPreinstalledCacheFileName = 'extraapps.txt';
const Duration kPreinstalledScanDelay = Duration(milliseconds: 100);

enum AppActionType { install, update, delete }

enum AppActionStage { download, upload }

@immutable
class AppAction {
  final String appId;
  final AppActionType type;
  final AppActionStage stage;
  final double progress;
  final String? error;

  const AppAction({
    required this.appId,
    required this.type,
    this.stage = AppActionStage.download,
    this.progress = 0,
    this.error,
  });

  AppAction copyWith({
    AppActionStage? stage,
    double? progress,
    String? error,
  }) => AppAction(
    appId: appId,
    type: type,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    error: error,
  );
}

enum AppButtonState {
  install,
  update,
  preinstalled,
  installed,
  unsupported,
  inProgress,
}

class _PreinstalledCache {
  final String firmwareFingerprint;
  final Map<String, String> apps;

  const _PreinstalledCache({
    required this.firmwareFingerprint,
    required this.apps,
  });

  factory _PreinstalledCache.parse(String body) {
    final lines = body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    String? firmwareFingerprint;
    final apps = <String, String>{};

    for (final line in lines) {
      final index = line.indexOf(';');
      if (index < 0) continue;
      final first = line.substring(0, index).trim();
      final second = line.substring(index + 1).trim();
      if (firmwareFingerprint == null) {
        firmwareFingerprint = '$first;$second';
        continue;
      }
      final path = _restorePath(second);
      if (first.isNotEmpty && path.isNotEmpty) {
        apps[first] = path;
      }
    }

    return _PreinstalledCache(
      firmwareFingerprint: firmwareFingerprint ?? '',
      apps: Map.unmodifiable(apps),
    );
  }

  String encode() {
    final lines = <String>[firmwareFingerprint];
    for (final entry in apps.entries) {
      lines.add('${entry.key};${_cachePath(entry.value)}');
    }
    return '${lines.join('\n')}\n';
  }

  static String _cachePath(String path) {
    final trimmed = path.trim();
    const prefix = '$kAppsRoot/';
    if (trimmed.startsWith(prefix)) return trimmed.substring(prefix.length);
    return trimmed;
  }

  static String _restorePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed.startsWith('/')) return trimmed;
    return '$kAppsRoot/$trimmed';
  }
}

class AppsInstallService extends ChangeNotifier {
  AppsInstallService({required this.client, required this.api});

  final FlipperClient client;
  final AppsCatalogApi api;

  final Set<String> _installedAliases = {};
  Set<String> get installedAliases => Set.unmodifiable(_installedAliases);
  final Map<String, AppManifest> _installedManifests = {};
  final Set<String> _preinstalledAliases = {};
  final Map<String, String> _preinstalledPaths = {};
  final Map<String, String> _categoryNamesById = {};
  Map<String, String> _firmwareMetadata = const {};

  final Map<String, AppAction> _actions = {};
  Map<String, AppAction> get actions => Map.unmodifiable(_actions);

  bool _scanning = false;
  bool get scanning => _scanning;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  bool isInstalled(AppCard app) =>
      app.alias.isNotEmpty &&
      (_installedAliases.contains(app.alias) ||
          _preinstalledAliases.contains(app.alias));

  bool isPreinstalled(AppCard app) =>
      app.alias.isNotEmpty &&
      _preinstalledAliases.contains(app.alias) &&
      !_installedAliases.contains(app.alias);

  AppAction? actionFor(AppCard app) =>
      app.alias.isEmpty ? null : _actions[app.alias];

  AppButtonState buttonState(AppCard app) {
    if (app.alias.isEmpty) return AppButtonState.install;
    final action = _actions[app.alias];
    if (action != null) return AppButtonState.inProgress;
    final manifest = _installedManifests[app.alias];
    final preinstalled = isPreinstalled(app);

    final cv = app.currentVersion;
    if (cv == null) {
      return preinstalled
          ? AppButtonState.preinstalled
          : isInstalled(app)
          ? AppButtonState.installed
          : AppButtonState.unsupported;
    }

    final build = cv.currentBuild;
    if (build == null || build.sdk == null) {
      return preinstalled
          ? AppButtonState.preinstalled
          : isInstalled(app)
          ? AppButtonState.installed
          : AppButtonState.unsupported;
    }

    if (preinstalled) {
      return AppButtonState.preinstalled;
    }

    if (manifest != null) {
      final deviceApi = api.api;
      if (manifest.versionUid.isNotEmpty &&
          cv.id.isNotEmpty &&
          manifest.versionUid != cv.id) {
        return AppButtonState.update;
      }
      if (deviceApi != null &&
          deviceApi.isNotEmpty &&
          manifest.sdkApi.isNotEmpty &&
          manifest.sdkApi != deviceApi) {
        return AppButtonState.update;
      }
    }

    return isInstalled(app) ? AppButtonState.installed : AppButtonState.install;
  }

  Future<void> refreshInstalled() async {
    if (!isReady) {
      _installedAliases.clear();
      _installedManifests.clear();
      _preinstalledAliases.clear();
      _preinstalledPaths.clear();
      _firmwareMetadata = const {};
      notifyListeners();
      return;
    }
    _scanning = true;
    notifyListeners();
    try {
      await _ensureDeviceFilters();
      final list = await client.storageList(
        ListRequest(path: kManifestsRoot),
        timeout: const Duration(seconds: 20),
      );
      _installedAliases.clear();
      _installedManifests.clear();
      _preinstalledAliases.clear();
      _preinstalledPaths.clear();
      for (final item in list.items) {
        for (final f in item.file) {
          if (f.type != File_FileType.FILE) continue;
          if (!f.name.endsWith('.fim')) continue;
          final alias = f.name.substring(0, f.name.length - 4);
          if (alias.isEmpty) continue;
          _installedAliases.add(alias);
          final manifest = await _readManifest('$kManifestsRoot/${f.name}');
          if (manifest != null) {
            _installedManifests[alias] = manifest;
          }
        }
      }
      final cached = await _readPreinstalledCache();
      if (cached != null &&
          cached.firmwareFingerprint == _firmwareFingerprint()) {
        _restorePreinstalledFromCache(cached.apps);
        LogService.log(
          '[AppsInstall] preinstalled cache restored: ${_preinstalledAliases.length} apps',
        );
      } else {
        await _scanPreinstalledApps();
        await _writePreinstalledCache();
      }
    } catch (e) {
      LogService.log('[AppsInstall] refresh failed: $e');
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<bool> installOrUpdate(
    AppCard app, {
    AppCategory? category,
    AppDetail? detail,
  }) async {
    if (!isReady || app.alias.isEmpty) return false;

    final wasInstalled =
        _installedAliases.contains(app.alias) ||
        _preinstalledAliases.contains(app.alias);
    final action = AppAction(
      appId: app.alias,
      type: wasInstalled ? AppActionType.update : AppActionType.install,
    );
    _actions[app.alias] = action;
    notifyListeners();

    await _ensureDeviceFilters();

    final existingManifest = _installedManifests[app.alias];
    final installDir = await _resolveInstallDir(
      app,
      category: category,
      manifest: existingManifest,
    );
    final fapPath = existingManifest?.path.isNotEmpty == true
        ? existingManifest!.path
        : '$installDir/${app.alias}.fap';
    final fimPath = '$kManifestsRoot/${app.alias}.fim';
    final tempFap = _tempFapPath(app);
    final tempFim = _tempFimPath(app);

    try {
      var cv = detail?.card.currentVersion ?? app.currentVersion;
      var build = cv?.currentBuild;
      if (cv == null || cv.id.isEmpty || build == null) {
        final fetched = await api.fetchApp(app.alias);
        cv = fetched.card.currentVersion;
        build = cv?.currentBuild;
      }
      if (cv == null || cv.id.isEmpty || build == null) {
        throw StateError('No installable version available');
      }

      final iconBase64 = await _fetchIconBase64(cv.iconUri);
      final manifest = AppManifest(
        uid: app.id,
        versionUid: cv.id,
        fullName: cv.name.isNotEmpty ? cv.name : app.name,
        path: fapPath,
        iconBase64: iconBase64,
        sdkApi: api.api ?? build.sdk?.api ?? '',
        devCatalog: false,
      );
      final manifestBytes = utf8.encode(manifest.encode());
      final fapBytes = await api.fetchFapBuild(
        cv.id,
        onProgress: (receivedBytes, totalBytes) {
          if (totalBytes == null || totalBytes <= 0) return;
          _setActionState(
            app.alias,
            stage: AppActionStage.download,
            progress: receivedBytes / totalBytes,
          );
        },
      );
      _setActionState(app.alias, stage: AppActionStage.download, progress: 1.0);

      await _ensureDir(kTempRoot);
      await _ensureDir(kAppsRoot);
      await _ensureDir(installDir);
      await _ensureDir(kManifestsRoot);

      await _safeDelete(tempFap);
      await _safeDelete(tempFim);

      await client.storageWriteChunked(
        tempFap,
        fapBytes,
        onProgress: (p) => _setActionState(
          app.alias,
          stage: AppActionStage.upload,
          progress: p,
        ),
      );

      await client.storageWriteChunked(tempFim, manifestBytes);
      _setActionState(app.alias, stage: AppActionStage.upload, progress: 1.0);

      await _safeDelete(fapPath);
      await _safeDelete(fimPath);

      await client.storageRename(
        RenameRequest(oldPath: tempFap, newPath: fapPath),
        timeout: const Duration(seconds: 30),
      );
      await client.storageRename(
        RenameRequest(oldPath: tempFim, newPath: fimPath),
        timeout: const Duration(seconds: 30),
      );

      _installedAliases.add(app.alias);
      _installedManifests[app.alias] = manifest;
      _preinstalledAliases.remove(app.alias);
      _preinstalledPaths.remove(app.alias);
      await _removePreinstalledFromCache(app.alias);
      _actions.remove(app.alias);
      notifyListeners();
      return true;
    } catch (e) {
      LogService.log('[AppsInstall] install ${app.alias} failed: $e');
      _actions[app.alias] = action.copyWith(error: '$e');
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 2));
      _actions.remove(app.alias);
      notifyListeners();
      return false;
    }
  }

  Future<bool> uninstall(AppCard app, {AppCategory? category}) async {
    if (!isReady || app.alias.isEmpty) return false;
    final action = AppAction(appId: app.alias, type: AppActionType.delete);
    _actions[app.alias] = action;
    notifyListeners();
    try {
      final fimPath = '$kManifestsRoot/${app.alias}.fim';
      final fapPath =
          _installedManifests[app.alias]?.path ??
          _preinstalledPaths[app.alias] ??
          '${await _resolveInstallDir(app, category: category)}/${app.alias}.fap';
      await _safeDelete(fimPath);
      await _safeDelete(fapPath);
      _installedAliases.remove(app.alias);
      _installedManifests.remove(app.alias);
      _preinstalledAliases.remove(app.alias);
      _preinstalledPaths.remove(app.alias);
      await _removePreinstalledFromCache(app.alias);
      _actions.remove(app.alias);
      notifyListeners();
      return true;
    } catch (e) {
      LogService.log('[AppsInstall] uninstall ${app.alias} failed: $e');
      _actions[app.alias] = action.copyWith(error: '$e');
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 2));
      _actions.remove(app.alias);
      notifyListeners();
      return false;
    }
  }

  Future<void> launch(AppCard app, {AppCategory? category}) async {
    if (!isReady) {
      throw StateError('Flipper is not connected');
    }
    final path =
        _installedManifests[app.alias]?.path ??
        _preinstalledPaths[app.alias] ??
        '${await _resolveInstallDir(app, category: category)}/${app.alias}.fap';
    await client.appStart(
      StartRequest(name: path, args: ''),
      timeout: const Duration(seconds: 15),
    );
  }

  bool _scannedOnce = false;

  Future<void> ensureScanned() async {
    if (!isReady) return;
    if (_scannedOnce) return;
    await _ensureDeviceFilters();
    await refreshInstalled();
    _scannedOnce = true;
  }

  Future<void> rescanInstalled() async {
    if (!isReady) return;
    await _ensureDeviceFilters();
    await refreshInstalled();
    _scannedOnce = true;
  }

  Future<void> _ensureDeviceFilters() async {
    if (api.target != null && api.api != null && _firmwareMetadata.isNotEmpty) {
      return;
    }
    try {
      final res = await client.deviceInfo(timeout: const Duration(seconds: 10));
      final info = <String, String>{};
      for (final item in res.items) {
        final key = item.key.trim();
        final value = item.value.trim();
        if (key.isEmpty || value.isEmpty) continue;
        info[key] = value;
      }

      final target = _firstInfoValue(info, const [
        'hardware_target',
        'hardware.target',
        'target',
      ]);
      final major = _firstInfoValue(info, const [
        'firmware_api_major',
        'firmware.api.major',
        'api.major',
        'api_major',
      ]);
      final minor = _firstInfoValue(info, const [
        'firmware_api_minor',
        'firmware.api.minor',
        'api.minor',
        'api_minor',
      ]);
      if (target != null) api.target = 'f$target';
      if (major != null) api.api = '$major.${minor ?? '0'}';

      final metadata = <String, String>{};
      void add(String name, List<String> keys) {
        final value = _firstInfoValue(info, keys);
        if (value != null && value.isNotEmpty) {
          metadata[name] = value;
        }
      }

      add('firmware_version', const [
        'devinfo_firmware.version',
        'firmware.version',
        'firmware_version',
        'software_revision',
      ]);
      add('firmware_build_date', const [
        'devinfo_firmware.build.date',
        'firmware.build.date',
        'firmware_build_date',
        'build_date',
        'datetime',
      ]);
      _firmwareMetadata = Map.unmodifiable(metadata);
    } catch (e) {
      LogService.log('[AppsInstall] deviceInfo failed: $e');
    }
  }

  Future<void> _ensureDir(String path) async {
    try {
      await client.storageMkdir(MkdirRequest(path: path));
    } catch (_) {}
  }

  Future<void> _safeDelete(String path) async {
    try {
      await client.storageDelete(DeleteRequest(path: path, recursive: false));
    } catch (_) {}
  }

  Future<void> _scanPreinstalledApps() async {
    try {
      final root = await client.storageList(
        ListRequest(path: kAppsRoot),
        timeout: const Duration(seconds: 20),
      );
      final categoryDirs = <String>[];
      for (final item in root.items) {
        for (final f in item.file) {
          if (f.type == File_FileType.DIR && f.name.isNotEmpty) {
            categoryDirs.add(f.name);
          }
        }
      }
      LogService.log(
        '[AppsInstall] preinstalled scan: ${categoryDirs.length} categories in $kAppsRoot',
      );

      for (var i = 0; i < categoryDirs.length; i++) {
        final dirName = categoryDirs[i];
        LogService.log(
          '[AppsInstall] preinstalled scan category ${i + 1}/${categoryDirs.length}: $dirName',
        );
        await _scanPreinstalledCategory('$kAppsRoot/$dirName');
        if (i != categoryDirs.length - 1) {
          await Future<void>.delayed(kPreinstalledScanDelay);
        }
      }
      LogService.log(
        '[AppsInstall] preinstalled scan done: ${_preinstalledAliases.length} manifestless apps found',
      );
    } catch (e) {
      LogService.log('[AppsInstall] preinstalled scan failed: $e');
    }
  }

  void _restorePreinstalledFromCache(Map<String, String> apps) {
    _preinstalledAliases.clear();
    _preinstalledPaths.clear();
    for (final entry in apps.entries) {
      final alias = entry.key.trim();
      final path = entry.value.trim();
      if (alias.isEmpty || path.isEmpty || _installedAliases.contains(alias)) {
        continue;
      }
      _preinstalledAliases.add(alias);
      _preinstalledPaths[alias] = path;
    }
  }

  Future<_PreinstalledCache?> _readPreinstalledCache() async {
    try {
      final file = await _preinstalledCacheFile();
      if (!await file.exists()) {
        await _migrateLegacyPreinstalledCache(file);
      }
      if (!await file.exists()) return null;
      final body = await file.readAsString();
      if (body.trim().isEmpty) return null;
      return _PreinstalledCache.parse(body);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePreinstalledCache({
    Map<String, String>? apps,
    String? firmwareFingerprint,
  }) async {
    final fingerprint = firmwareFingerprint ?? _firmwareFingerprint();
    if (fingerprint.isEmpty) return;
    try {
      final cache = _PreinstalledCache(
        firmwareFingerprint: fingerprint,
        apps: Map.unmodifiable(apps ?? _preinstalledPaths),
      );
      final file = await _preinstalledCacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(cache.encode(), flush: true);
    } catch (e) {
      LogService.log('[AppsInstall] preinstalled cache write failed: $e');
    }
  }

  Future<io.File> _preinstalledCacheFile() async {
    final root = await appDocumentsDirectory();
    final deviceName =
        normalizeFlipperDeviceName(client.connectedDevice?.name) ?? 'Flipper';
    return io.File(
      pathJoin([
        root.path,
        sanitizePathSegment(deviceName),
        'manifest',
        kPreinstalledCacheFileName,
      ]),
    );
  }

  Future<void> _migrateLegacyPreinstalledCache(io.File target) async {
    final candidates = <io.File>[
      io.File(
        pathJoin([
          (await legacyApplicationDocumentsDirectory(['qunleashed'])).path,
          'apps',
          'manifest',
          kPreinstalledCacheFileName,
        ]),
      ),
      io.File(
        pathJoin([
          (await userDocumentsDirectory()).path,
          'qunleashed',
          'apps',
          'manifest',
          kPreinstalledCacheFileName,
        ]),
      ),
      io.File(
        pathJoin([
          (await userDocumentsDirectory()).path,
          kAppDocumentsFolderName,
          'apps',
          'manifest',
          kPreinstalledCacheFileName,
        ]),
      ),
    ];
    for (final file in candidates) {
      if (!await file.exists()) continue;
      await target.parent.create(recursive: true);
      await file.copy(target.path);
      return;
    }
  }

  Future<void> _removePreinstalledFromCache(String alias) async {
    if (alias.isEmpty) return;
    final cached = await _readPreinstalledCache();
    if (cached == null || !cached.apps.containsKey(alias)) return;
    _preinstalledAliases.remove(alias);
    _preinstalledPaths.remove(alias);
    final apps = Map<String, String>.from(cached.apps)..remove(alias);
    await _writePreinstalledCache(
      apps: apps,
      firmwareFingerprint: cached.firmwareFingerprint,
    );
  }

  String? _firstInfoValue(Map<String, String> info, List<String> keys) {
    for (final key in keys) {
      final value = info[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _firmwareFingerprint() {
    final version = _firmwareMetadata['firmware_version'] ?? '';
    final buildDate = _firmwareMetadata['firmware_build_date'] ?? '';
    if (version.isEmpty && buildDate.isEmpty) return '';
    return '$version;$buildDate';
  }

  Future<void> _scanPreinstalledCategory(String path) async {
    try {
      final list = await client.storageList(
        ListRequest(path: path),
        timeout: const Duration(seconds: 20),
      );
      for (final item in list.items) {
        for (final f in item.file) {
          if (f.type != File_FileType.FILE) continue;
          if (!f.name.endsWith('.fap')) continue;
          final alias = f.name.substring(0, f.name.length - 4);
          if (alias.isEmpty || _installedAliases.contains(alias)) continue;
          _preinstalledAliases.add(alias);
          _preinstalledPaths[alias] = '$path/${f.name}';
          LogService.log(
            '[AppsInstall] preinstalled found: alias=$alias path=${_preinstalledPaths[alias]}',
          );
        }
      }
    } catch (e) {
      LogService.log('[AppsInstall] preinstalled category "$path" failed: $e');
    }
  }

  void _setActionState(
    String appId, {
    AppActionStage? stage,
    double? progress,
  }) {
    final current = _actions[appId];
    if (current == null) return;
    _actions[appId] = current.copyWith(
      stage: stage,
      progress: (progress ?? current.progress).clamp(0, 1).toDouble(),
    );
    notifyListeners();
  }

  Future<String> _fetchIconBase64(String url) async {
    if (url.isEmpty) return '';
    try {
      final http = io.HttpClient();
      try {
        final req = await http.getUrl(Uri.parse(url));
        final res = await req.close();
        if (res.statusCode != 200) return '';
        final bytes = <int>[];
        await for (final chunk in res) {
          bytes.addAll(chunk);
        }
        return base64Encode(bytes);
      } finally {
        http.close(force: true);
      }
    } catch (_) {
      return '';
    }
  }

  Future<AppManifest?> _readManifest(String path) async {
    try {
      final res = await client.storageRead(
        ReadRequest(path: path),
        timeout: const Duration(seconds: 20),
      );
      final bytes = <int>[];
      for (final item in res.items) {
        if (item.hasFile()) bytes.addAll(item.file.data);
      }
      if (bytes.isEmpty) return null;
      return AppManifest.tryParse(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      LogService.log('[AppsInstall] read manifest "$path" failed: $e');
      return null;
    }
  }

  Future<String> _resolveInstallDir(
    AppCard app, {
    AppCategory? category,
    AppManifest? manifest,
  }) async {
    final manifestPath =
        manifest?.path ??
        _installedManifests[app.alias]?.path ??
        _preinstalledPaths[app.alias];
    if (manifestPath != null && manifestPath.isNotEmpty) {
      final lastSlash = manifestPath.lastIndexOf('/');
      if (lastSlash > 0) return manifestPath.substring(0, lastSlash);
    }
    final categoryAlias = await _resolveCategoryAlias(category, app.categoryId);
    return '$kAppsRoot/$categoryAlias';
  }

  Future<String> _resolveCategoryAlias(
    AppCategory? category,
    String categoryId,
  ) async {
    final direct = category?.name.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final cached = _categoryNamesById[categoryId];
    if (cached != null && cached.isNotEmpty) return cached;
    if (categoryId.isNotEmpty) {
      try {
        final categories = await api.fetchCategories();
        for (final item in categories) {
          if (item.id.isNotEmpty && item.name.isNotEmpty) {
            _categoryNamesById[item.id] = item.name;
          }
        }
        final resolved = _categoryNamesById[categoryId];
        if (resolved != null && resolved.isNotEmpty) return resolved;
      } catch (e) {
        LogService.log(
          '[AppsInstall] resolve category "$categoryId" failed: $e',
        );
      }
    }
    if (categoryId.isNotEmpty) return categoryId;
    return 'Misc';
  }

  String _tempFapPath(AppCard app) => '$kTempRoot/${_tempKey(app)}.fap';
  String _tempFimPath(AppCard app) => '$kTempRoot/${_tempKey(app)}.fim';

  String _tempKey(AppCard app) {
    final raw = app.id.isNotEmpty ? app.id : app.alias;
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
