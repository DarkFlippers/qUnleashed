import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/http/app_http.dart';
import '../../../services/progress_throttle.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../components/codec/fap/icon.dart';
import '../../../services/assembler/build_service.dart';
import '../../../services/assembler/controller.dart';
import '../../../services/assembler/remote_build_service.dart';
import 'catalog_context.dart';
import 'catalog_api.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'models/detail.dart';
import 'models/manifest.dart';
import '../../../services/logging.dart';

enum AppActionType { install, update, delete }

enum AppActionStage { queued, download, build, upload, check }

@immutable
class AppAction {
  final String alias;
  final AppActionType type;
  final AppActionStage stage;
  final double progress;
  final String? error;

  const AppAction({
    required this.alias,
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
    alias: alias,
    type: type,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    error: error,
  );
}

class InstallEngine extends ChangeNotifier {
  InstallEngine({
    required this.client,
    required this.api,
    required this.manifests,
    required this.catalog,
    required this.onInstalled,
  });

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final CatalogContext catalog;

  /// Called after a successful install so the device list can adopt the app
  /// without the engine reaching into its sibling registry.
  final Future<void> Function({
    required String alias,
    required String devicePath,
    required List<int> fapBytes,
  })
  onInstalled;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  final Map<String, AppAction> _actions = {};
  Map<String, AppAction> get actions => Map.unmodifiable(_actions);

  AppAction? actionFor(AppCard app) =>
      app.alias.isEmpty ? null : _actions[app.alias];

  bool isInstalled(AppCard app) {
    if (app.id.isNotEmpty && manifests.byUid(app.id) != null) return true;
    return app.alias.isNotEmpty && manifests.byAlias(app.alias) != null;
  }

  final Map<String, String> _categoryNamesById = {};

  final List<_AppTask> _taskQueue = [];
  final Map<String, _PreparedInstall> _preparedInstalls = {};
  bool _taskWorkerRunning = false;
  final Stopwatch _sinceLastTask = Stopwatch();
  final ProgressThrottle _progressThrottle = ProgressThrottle();
  static const int _maxLinkRetries = 5;

  Future<bool> _enqueueTask(
    String alias,
    Future<bool> Function() run, {
    bool needsLink = false,
  }) {
    final task = _AppTask(alias, run, needsLink: needsLink);
    _taskQueue.add(task);
    unawaited(_drainTaskQueue());
    return task.done.future;
  }

  Future<void> _drainTaskQueue() async {
    if (_taskWorkerRunning) return;
    _taskWorkerRunning = true;
    try {
      while (_taskQueue.isNotEmpty) {
        if (!isReady && _taskQueue.first.needsLink) break;
        if (_sinceLastTask.isRunning) {
          final wait = kTaskCooldown - _sinceLastTask.elapsed;
          if (wait > Duration.zero) await Future<void>.delayed(wait);
          _sinceLastTask
            ..stop()
            ..reset();
        }
        if (_taskQueue.isEmpty) break;
        final task = _taskQueue.removeAt(0);
        var ok = false;
        var requeued = false;
        try {
          ok = await task.run();
        } on _LinkDroppedException {
          task.attempts += 1;
          task.needsLink = true;
          requeued =
              task.attempts <= _maxLinkRetries &&
              _actions.containsKey(task.alias);
          if (requeued) {
            _taskQueue.insert(0, task);
          } else {
            _preparedInstalls.remove(task.alias);
            if (_clearAction(task.alias)) notifyListeners();
          }
        } catch (e) {
          LogService.log('[InstallEngine] task "${task.alias}" failed: $e');
          if (_clearAction(task.alias)) notifyListeners();
        }
        if (requeued) continue;
        if (!task.done.isCompleted) task.done.complete(ok);
        _sinceLastTask
          ..reset()
          ..start();
      }
    } finally {
      _taskWorkerRunning = false;
    }
  }

  bool get _remoteBuildMode =>
      catalog.sourceBuildEnabled &&
      AssemblerController.instance.usesServerBuild;

  String? _serverBuildAlias;

  /// The server takes one job at a time, so a second install has to wait. The
  /// occupied alias is tracked instead of scanning [actions] because callers
  /// ask on every tap.
  String? serverBuildBlocker(String alias) {
    final active = _serverBuildAlias;
    return active != null && active != alias ? active : null;
  }

  /// Every path that finishes an action goes through here so the server slot
  /// is released exactly once.
  bool _clearAction(String alias) {
    final removed = _actions.remove(alias) != null;
    if (_serverBuildAlias == alias) _serverBuildAlias = null;
    return removed;
  }

  Future<bool> installOrUpdate(
    AppCard app, {
    AppCategory? category,
    AppDetail? detail,
  }) {
    if (!isReady || app.alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(app.alias)) return Future.value(false);

    final wasInstalled = isInstalled(app);
    if (_remoteBuildMode) _serverBuildAlias = app.alias;
    _actions[app.alias] = AppAction(
      alias: app.alias,
      type: wasInstalled ? AppActionType.update : AppActionType.install,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(
      app.alias,
      () => _performInstall(app, category: category, detail: detail),
    );
  }

  Future<bool> _performInstall(
    AppCard app, {
    AppCategory? category,
    AppDetail? detail,
  }) async {
    final action = _actions[app.alias];
    if (action == null) return false;

    try {
      var prepared = _preparedInstalls[app.alias];
      if (prepared == null) {
        _setActionState(app.alias, stage: AppActionStage.download, progress: 0);
        if ((api.target == null || api.api == null) && !isReady) {
          throw const _LinkDroppedException();
        }
        await catalog.ensureDeviceFilters(required: true);

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

        final existingManifest = manifests.byAlias(app.alias);
        final installDir = await _resolveInstallDir(
          app,
          category: category,
          manifest: existingManifest,
        );
        final fapPath = existingManifest?.path.isNotEmpty == true
            ? existingManifest!.path
            : '$installDir/${app.alias}.fap';

        final iconBase64 = await _fetchIconBase64(cv.iconUri);
        final buildApi = build.sdk?.api ?? api.api ?? '';
        final manifest = AppManifest(
          uid: app.id,
          versionUid: cv.id,
          fullName: cv.name.isNotEmpty ? cv.name : app.name,
          path: fapPath,
          iconBase64: iconBase64,
          sdkApi: buildApi,
          devCatalog: false,
        );

        void onProgress(int receivedBytes, int? totalBytes) {
          if (totalBytes == null || totalBytes <= 0) return;
          _setActionState(
            app.alias,
            stage: AppActionStage.download,
            progress: receivedBytes / totalBytes,
          );
        }

        List<int> fapBytes;
        if (catalog.sourceBuildEnabled) {
          if (!AssemblerController.instance.usesServerBuild) {
            final bundle = await api.fetchSourceBundle(
              cv.id,
              onProgress: onProgress,
            );
            _setActionState(
              app.alias,
              stage: AppActionStage.build,
              progress: 0,
            );
            fapBytes = await AssemblerBuildService.buildFromBundle(
              bundle: bundle,
              alias: app.alias,
            );
            _setActionState(
              app.alias,
              stage: AppActionStage.build,
              progress: 1,
            );
          } else {
            fapBytes = await _buildOnServer(app, cv);
          }
        } else {
          try {
            fapBytes = await api.fetchFapBuild(cv.id, onProgress: onProgress);
          } on AppHttpException catch (e) {
            if (e.statusCode != 404) rethrow;
            var appApi = buildApi;
            if (appApi.isEmpty) {
              try {
                final d = await api.fetchApp(app.alias);
                appApi = d.card.currentVersion?.currentBuild?.sdk?.api ?? '';
              } catch (_) {}
            }
            final canFallback = appApi.isNotEmpty && appApi != api.api;
            if (canFallback && catalog.apiFallbackEnabled) {
              fapBytes = await api.fetchFapBuild(
                cv.id,
                onProgress: onProgress,
                apiOverride: appApi,
              );
            } else {
              throw StateError(
                canFallback
                    ? 'App is built for API $appApi, firmware has '
                          '${api.api ?? '?'}; switch the catalog mode in the '
                          'apps settings to install it'
                    : 'No compatible build for this firmware (API ${api.api ?? '?'})',
              );
            }
          }
        }
        _setActionState(app.alias, stage: AppActionStage.download, progress: 1);

        unawaited(_cacheFapIcon(app.alias, fapBytes));

        prepared = _PreparedInstall(manifest: manifest, fapBytes: fapBytes);
        _preparedInstalls[app.alias] = prepared;
      }

      if (!isReady) throw const _LinkDroppedException();

      final manifest = prepared.manifest;
      final fapPath = manifest.path;
      final fimPath = '$kManifestsRoot/${app.alias}.fim';
      final manifestBytes = utf8.encode(manifest.encode());
      final lastSlash = fapPath.lastIndexOf('/');
      final installDir = lastSlash > 0
          ? fapPath.substring(0, lastSlash)
          : kAppsRoot;

      await _ensureDir(kAppsRoot);
      await _ensureDir(installDir);
      await _ensureDir(kManifestsRoot);

      await client.storageWriteChunked(
        fapPath,
        prepared.fapBytes,
        onProgress: (p) => _setActionState(
          app.alias,
          stage: AppActionStage.upload,
          progress: p,
        ),
      );
      _setActionState(app.alias, stage: AppActionStage.check, progress: 1);
      await _verifyUpload(fapPath, prepared.fapBytes);

      await client.storageWriteChunked(fimPath, manifestBytes);
      await _verifyUpload(fimPath, manifestBytes);

      manifests.put(app.alias, manifest, fimSize: manifestBytes.length);
      await onInstalled(
        alias: app.alias,
        devicePath: fapPath,
        fapBytes: prepared.fapBytes,
      );
      _preparedInstalls.remove(app.alias);
      _clearAction(app.alias);
      notifyListeners();
      return true;
    } catch (e) {
      if (e is _LinkDroppedException || !isReady) {
        _setActionState(app.alias, stage: AppActionStage.queued, progress: 0);
        throw const _LinkDroppedException();
      }
      _preparedInstalls.remove(app.alias);
      LogService.log('[InstallEngine] install ${app.alias} failed: $e');
      _actions[app.alias] = (_actions[app.alias] ?? action).copyWith(
        error: '$e',
      );
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 2));
      _clearAction(app.alias);
      notifyListeners();
      return false;
    }
  }

  Future<List<int>> _buildOnServer(AppCard app, AppCurrentVersion cv) {
    _setActionState(app.alias, stage: AppActionStage.queued, progress: 0);
    return RemoteBuildService.instance.build(
      bundleUrl: api.sourceBundleUri(cv.id).toString(),
      alias: app.alias,
      target: catalog.deviceTarget ?? 'f7',
      api: catalog.deviceApi,
      uid: app.id,
      versionUid: cv.id,
      onPhase: (phase, progress) {
        switch (phase) {
          case RemoteBuildPhase.queued:
            _setActionState(
              app.alias,
              stage: AppActionStage.queued,
              progress: 0,
            );
          case RemoteBuildPhase.building:
            _setActionState(
              app.alias,
              stage: AppActionStage.build,
              progress: 0,
            );
          case RemoteBuildPhase.download:
            _setActionState(
              app.alias,
              stage: AppActionStage.download,
              progress: progress,
            );
        }
      },
    );
  }

  Future<bool> uninstall(AppCard app, {AppCategory? category}) {
    if (!isReady || app.alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(app.alias)) return Future.value(false);
    _actions[app.alias] = AppAction(
      alias: app.alias,
      type: AppActionType.delete,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(
      app.alias,
      () => _performUninstall(app, category: category),
      needsLink: true,
    );
  }

  Future<bool> _performUninstall(AppCard app, {AppCategory? category}) async {
    final action = _actions[app.alias];
    if (action == null) return false;
    if (!isReady) throw const _LinkDroppedException();
    _setActionState(app.alias, stage: AppActionStage.download);
    try {
      final fimPath = '$kManifestsRoot/${app.alias}.fim';
      final fapPath =
          manifests.byAlias(app.alias)?.path ??
          '${await _resolveInstallDir(app, category: category)}/${app.alias}.fap';
      await _safeDelete(fimPath);
      await _safeDelete(fapPath);
      manifests.removeAlias(app.alias);
      _clearAction(app.alias);
      notifyListeners();
      return true;
    } catch (e) {
      if (!isReady) {
        _setActionState(app.alias, stage: AppActionStage.queued, progress: 0);
        throw const _LinkDroppedException();
      }
      LogService.log('[InstallEngine] uninstall ${app.alias} failed: $e');
      _actions[app.alias] = (_actions[app.alias] ?? action).copyWith(
        error: '$e',
      );
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 2));
      _clearAction(app.alias);
      notifyListeners();
      return false;
    }
  }

  Future<void> launch(AppCard app, {AppCategory? category}) async {
    if (!isReady) throw StateError('Device is not connected');
    final path =
        manifests.byAlias(app.alias)?.path ??
        '${await _resolveInstallDir(app, category: category)}/${app.alias}.fap';
    await client.appStart(
      StartRequest(name: path, args: ''),
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> launchPath(String path) async {
    if (!isReady) throw StateError('Device is not connected');
    await client.appStart(
      StartRequest(name: path, args: ''),
      timeout: const Duration(seconds: 15),
    );
  }

  Future<bool> deleteInstalled({
    required String alias,
    required String fapPath,
  }) {
    if (!isReady || alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(alias)) return Future.value(false);
    _actions[alias] = AppAction(
      alias: alias,
      type: AppActionType.delete,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(alias, () async {
      _setActionState(alias, stage: AppActionStage.download);
      await _safeDelete('$kManifestsRoot/$alias.fim');
      await _safeDelete(fapPath);
      manifests.removeAlias(alias);
      _clearAction(alias);
      notifyListeners();
      return true;
    }, needsLink: true);
  }

  Future<bool> restore({
    required String alias,
    required String fapPath,
    required List<int> fapBytes,
    AppManifest? manifest,
  }) {
    if (!isReady || alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(alias)) return Future.value(false);
    _actions[alias] = AppAction(
      alias: alias,
      type: AppActionType.install,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(alias, () async {
      final lastSlash = fapPath.lastIndexOf('/');
      final dir = lastSlash > 0 ? fapPath.substring(0, lastSlash) : kAppsRoot;
      await _ensureDir(kAppsRoot);
      await _ensureDir(dir);
      await client.storageWriteChunked(
        fapPath,
        fapBytes,
        onProgress: (p) =>
            _setActionState(alias, stage: AppActionStage.upload, progress: p),
      );
      _setActionState(alias, stage: AppActionStage.check, progress: 1);
      await _verifyUpload(fapPath, fapBytes);
      if (manifest != null) {
        await _ensureDir(kManifestsRoot);
        final bytes = utf8.encode(manifest.encode());
        await client.storageWriteChunked('$kManifestsRoot/$alias.fim', bytes);
        await _verifyUpload('$kManifestsRoot/$alias.fim', bytes);
        manifests.put(alias, manifest, fimSize: bytes.length);
      }
      _clearAction(alias);
      notifyListeners();
      return true;
    }, needsLink: true);
  }

  void _setActionState(
    String alias, {
    AppActionStage? stage,
    double? progress,
  }) {
    final current = _actions[alias];
    if (current == null) return;
    final next = current.copyWith(
      stage: stage,
      progress: (progress ?? current.progress).clamp(0, 1).toDouble(),
    );
    _actions[alias] = next;
    final stageChanged = next.stage != current.stage;
    if (stageChanged) _progressThrottle.reset();
    if (stageChanged || _progressThrottle.shouldEmit(next.progress)) {
      notifyListeners();
    }
  }

  Future<void> _verifyUpload(String path, List<int> bytes) async {
    final expected = md5.convert(bytes).toString().toLowerCase();
    String actual;
    try {
      final batch = await client.storageMd5sum(
        Md5sumRequest(path: path),
        timeout: const Duration(seconds: 30),
      );
      actual = (batch.items.isNotEmpty ? batch.items.first.md5sum : '')
          .trim()
          .toLowerCase();
    } catch (e) {
      LogService.log('[InstallEngine] md5 of "$path" unavailable: $e');
      return;
    }
    if (actual.isEmpty) {
      LogService.log('[InstallEngine] md5 of "$path" came back empty');
      return;
    }
    if (actual != expected) {
      throw StateError(
        'Uploaded "$path" is corrupted: md5 $actual, expected $expected',
      );
    }
    LogService.log('[InstallEngine] md5 of "$path" verified');
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

  Future<String> _resolveInstallDir(
    AppCard app, {
    AppCategory? category,
    AppManifest? manifest,
  }) async {
    final manifestPath = manifest?.path ?? manifests.byAlias(app.alias)?.path;
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
          '[InstallEngine] resolve category "$categoryId" failed: $e',
        );
      }
    }
    return categoryId.isNotEmpty ? categoryId : 'Misc';
  }

  Future<String> _fetchIconBase64(String url) async {
    if (url.isEmpty) return '';
    try {
      return base64Encode(await AppHttp.getBytes(Uri.parse(url)));
    } catch (_) {
      return '';
    }
  }

  Future<void> _cacheFapIcon(String alias, List<int> fapBytes) async {
    if (alias.isEmpty) return;
    try {
      if (await hasFapIcon(alias)) return;
      final extracted = extractFapIcon(Uint8List.fromList(fapBytes));
      final icon = extracted?.icon;
      if (icon != null) await writeFapIcon(alias, icon);
    } catch (_) {}
  }

  void handleReset() {
    for (final task in _taskQueue) {
      if (!task.done.isCompleted) task.done.complete(false);
    }
    _taskQueue.clear();
    _actions.clear();
    _serverBuildAlias = null;
    _preparedInstalls.clear();
    notifyListeners();
  }
}

class _AppTask {
  _AppTask(this.alias, this.run, {this.needsLink = false});

  final String alias;
  final Future<bool> Function() run;
  final Completer<bool> done = Completer<bool>();
  int attempts = 0;
  bool needsLink;
}

class _PreparedInstall {
  _PreparedInstall({required this.manifest, required this.fapBytes});

  final AppManifest manifest;
  final List<int> fapBytes;
}

class _LinkDroppedException implements Exception {
  const _LinkDroppedException();
}
