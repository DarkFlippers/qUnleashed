import '../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/progress_throttle.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../components/codec/fap/icon.dart';
import 'binary_sources.dart';
import 'categories.dart';
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

  const AppAction({
    required this.alias,
    required this.type,
    this.stage = AppActionStage.download,
    this.progress = 0,
  });

  AppAction copyWith({AppActionStage? stage, double? progress}) => AppAction(
    alias: alias,
    type: type,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
  );
}

class InstallEngine extends ChangeNotifier {
  InstallEngine({
    required this.client,
    required this.api,
    required this.manifests,
    required this.catalog,
    required this.sources,
    required this.onInstalled,
  });

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final CatalogContext catalog;
  final AppSourceRegistry sources;

  /// Called after a successful install so the device list can adopt the app
  /// without the engine reaching into its sibling registry.
  final Future<void> Function({
    required String alias,
    required String devicePath,
    required List<int> fapBytes,
  })
  onInstalled;

  bool get isReady => client.isRpcReady;

  final Map<String, AppAction> _actions = {};
  Map<String, AppAction> get actions => Map.unmodifiable(_actions);

  AppAction? actionFor(AppCard app) =>
      app.alias.isEmpty ? null : _actions[app.alias];

  bool isInstalled(AppCard app) {
    if (app.id.isNotEmpty && manifests.byUid(app.id) != null) return true;
    return app.alias.isNotEmpty && manifests.byAlias(app.alias) != null;
  }

  final List<_AppTask> _taskQueue = [];
  final Map<String, _PreparedInstall> _preparedInstalls = {};
  final Set<String> _cancelling = {};
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
              _actions.containsKey(task.alias) &&
              !_cancelling.contains(task.alias);
          if (requeued) {
            _taskQueue.insert(0, task);
          } else {
            _preparedInstalls.remove(task.alias);
            if (_clearAction(task.alias)) notifyListeners();
          }
        } on FlipperWriteCancelledException {
          _preparedInstalls.remove(task.alias);
          if (_clearAction(task.alias)) notifyListeners();
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

  bool _clearAction(String alias) {
    _cancelling.remove(alias);
    return _actions.remove(alias) != null;
  }

  bool isCancelling(String alias) => _cancelling.contains(alias);

  /// A task that has not started yet simply leaves the queue. The running one
  /// cannot be torn out from under the device, so it is flagged and unwinds at
  /// its next checkpoint: the upload closes the firmware write stream and drops
  /// the partial file, the download and the server build stop being waited on.
  void cancel(String alias) {
    if (alias.isEmpty || !_actions.containsKey(alias)) return;
    final index = _taskQueue.indexWhere((task) => task.alias == alias);
    if (index >= 0) {
      final task = _taskQueue.removeAt(index);
      if (!task.done.isCompleted) task.done.complete(false);
      _preparedInstalls.remove(alias);
      _clearAction(alias);
      notifyListeners();
      return;
    }
    _cancelling.add(alias);
    notifyListeners();
  }

  void _throwIfCancelled(String alias) {
    if (_cancelling.contains(alias)) throw const _CancelledException();
  }

  Future<bool> installOrUpdate(
    AppCard app, {
    AppCategory? category,
    AppDetail? detail,
  }) {
    if (!isReady || app.alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(app.alias)) return Future.value(false);

    final wasInstalled = isInstalled(app);
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
    if (!_actions.containsKey(app.alias)) return false;

    try {
      var prepared = _preparedInstalls[app.alias];
      if (prepared == null) {
        _setActionState(app.alias, stage: AppActionStage.download, progress: 0);
        if ((api.target == null || api.api == null) && !isReady) {
          throw const _LinkDroppedException();
        }
        await catalog.ensureDeviceFilters(required: true);
        _throwIfCancelled(app.alias);

        final source = sources.forCard(app);

        var cv = detail?.card.currentVersion ?? app.currentVersion;
        if (cv == null || cv.id.isEmpty || cv.currentBuild == null) {
          final fetched = await api.fetchApp(app.alias);
          cv = fetched.card.currentVersion;
        }
        if (cv == null || cv.id.isEmpty || cv.currentBuild == null) {
          throw StateError(l10n.appsErrorNoVersion);
        }

        final existingManifest = manifests.byAlias(app.alias);
        final installDir = await _resolveInstallDir(
          app,
          category: category,
          manifest: existingManifest,
        );
        final fapPath = '$installDir/${app.alias}.fap';
        final previousPath = existingManifest?.path ?? '';
        if (previousPath.isNotEmpty && previousPath != fapPath) {
          LogService.log(
            '[InstallEngine] ${app.alias} moves from $previousPath to $fapPath',
          );
        }

        final manifest = AppManifest(
          uid: app.id,
          versionUid: cv.id,
          fullName: cv.name.isNotEmpty ? cv.name : app.name,
          path: fapPath,
          iconBase64: await source.iconBase64(app, cv),
          sdkApi: source.buildApi(app, cv),
          devCatalog: false,
        );

        final fapBytes = await source.fetch(
          app,
          version: cv,
          onProgress: (stage, progress) {
            // Throwing out of a progress callback tears down the HTTP stream,
            // which is the only way to stop a download in flight.
            _throwIfCancelled(app.alias);
            _setActionState(
              app.alias,
              stage: switch (stage) {
                BinaryStage.queued => AppActionStage.queued,
                BinaryStage.download => AppActionStage.download,
                BinaryStage.build => AppActionStage.build,
              },
              progress: progress,
            );
          },
          isCancelled: () => _cancelling.contains(app.alias),
        );
        _throwIfCancelled(app.alias);
        _setActionState(app.alias, stage: AppActionStage.download, progress: 1);

        unawaited(_cacheFapIcon(app.alias, fapBytes));

        prepared = _PreparedInstall(
          manifest: manifest,
          fapBytes: fapBytes,
          previousPath: previousPath,
        );
        _preparedInstalls[app.alias] = prepared;
      }

      _throwIfCancelled(app.alias);
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
        isCancelled: () => _cancelling.contains(app.alias),
      );
      _setActionState(app.alias, stage: AppActionStage.check, progress: 1);
      await _verifyUpload(fapPath, prepared.fapBytes);

      await client.storageWriteChunked(fimPath, manifestBytes);
      await _verifyUpload(fimPath, manifestBytes);

      if (prepared.previousPath.isNotEmpty &&
          prepared.previousPath != fapPath) {
        await _safeDelete(prepared.previousPath);
      }
      manifests.put(app.alias, manifest);
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
      if (_cancelling.contains(app.alias)) {
        _preparedInstalls.remove(app.alias);
        LogService.log('[InstallEngine] install ${app.alias} cancelled');
        _clearAction(app.alias);
        notifyListeners();
        return false;
      }
      if (e is _LinkDroppedException || !isReady) {
        _setActionState(app.alias, stage: AppActionStage.queued, progress: 0);
        throw const _LinkDroppedException();
      }
      _preparedInstalls.remove(app.alias);
      return _failAction(app.alias, e, 'install');
    }
  }

  Future<bool> _failAction(String alias, Object error, String what) async {
    LogService.log('[InstallEngine] $what $alias failed: $error');
    await Future<void>.delayed(const Duration(seconds: 2));
    _clearAction(alias);
    notifyListeners();
    return false;
  }

  Future<bool> uninstall(
    AppCard app, {
    AppCategory? category,
  }) => _enqueueDelete(
    app.alias,
    () async =>
        manifests.byAlias(app.alias)?.path ??
        '${await _resolveInstallDir(app, category: category)}/${app.alias}.fap',
  );

  Future<bool> deleteInstalled({
    required String alias,
    required String fapPath,
  }) => _enqueueDelete(alias, () async => fapPath);

  Future<bool> _enqueueDelete(
    String alias,
    Future<String> Function() resolveFapPath,
  ) {
    if (!isReady || alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(alias)) return Future.value(false);
    _actions[alias] = AppAction(
      alias: alias,
      type: AppActionType.delete,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(
      alias,
      () => _performDelete(alias, resolveFapPath),
      needsLink: true,
    );
  }

  Future<bool> _performDelete(
    String alias,
    Future<String> Function() resolveFapPath,
  ) async {
    if (!_actions.containsKey(alias)) return false;
    if (!isReady) throw const _LinkDroppedException();
    _setActionState(alias, stage: AppActionStage.download);
    try {
      final fapPath = await resolveFapPath();
      await _safeDelete('$kManifestsRoot/$alias.fim');
      await _safeDelete(fapPath);
      manifests.removeAlias(alias);
      _clearAction(alias);
      notifyListeners();
      return true;
    } catch (e) {
      if (!isReady) {
        _setActionState(alias, stage: AppActionStage.queued, progress: 0);
        throw const _LinkDroppedException();
      }
      return _failAction(alias, e, 'uninstall');
    }
  }

  Future<void> launch(AppCard app, {AppCategory? category}) async {
    await launchPath(
      manifests.byAlias(app.alias)?.path ??
          '${await _resolveInstallDir(app, category: category)}/${app.alias}.fap',
    );
  }

  Future<void> launchPath(String path) async {
    if (!isReady) throw StateError(l10n.appsErrorNotConnected);
    await client.appStart(
      StartRequest(name: path, args: ''),
      timeout: const Duration(seconds: 15),
    );
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
        isCancelled: () => _cancelling.contains(alias),
      );
      _setActionState(alias, stage: AppActionStage.check, progress: 1);
      await _verifyUpload(fapPath, fapBytes);
      if (manifest != null) {
        await _ensureDir(kManifestsRoot);
        final bytes = utf8.encode(manifest.encode());
        await client.storageWriteChunked('$kManifestsRoot/$alias.fim', bytes);
        await _verifyUpload('$kManifestsRoot/$alias.fim', bytes);
        manifests.put(alias, manifest);
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
    final fromIndex = sources.installDir(app.alias);
    if (fromIndex != null) return fromIndex;
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
    try {
      final resolved = await CategoryRegistry.instance.nameFor(api, categoryId);
      if (resolved != null) return resolved;
    } catch (e) {
      LogService.log(
        '[InstallEngine] resolve category "$categoryId" failed: $e',
      );
    }
    return categoryId.isNotEmpty ? categoryId : 'Misc';
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
    _preparedInstalls.clear();
    _cancelling.clear();
    notifyListeners();
  }

  /// A dropped link only pauses the queue: the worker stops at the first task
  /// that needs the device and [handleConnect] picks it up again. A disconnect
  /// with no reconnect behind it means nothing will ever drain the queue, so it
  /// ends here instead of hanging on a device that is gone.
  void handleDisconnect({required bool reconnecting}) {
    if (reconnecting) {
      notifyListeners();
      return;
    }
    handleReset();
  }

  void handleConnect() {
    unawaited(_drainTaskQueue());
    notifyListeners();
  }

  void handleDeviceChange() => handleReset();
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
  _PreparedInstall({
    required this.manifest,
    required this.fapBytes,
    this.previousPath = '',
  });

  final AppManifest manifest;
  final List<int> fapBytes;

  /// Where the app used to sit when the index moved it to another folder.
  final String previousPath;
}

class _LinkDroppedException implements Exception {
  const _LinkDroppedException();
}

class _CancelledException implements Exception {
  const _CancelledException();
}
