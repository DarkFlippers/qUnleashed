import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../services/http/app_http.dart' show AppHttpException;
import '../../../services/progress_throttle.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../components/codec/fap/icon.dart';
import '../../../services/assembler/built_file.dart';
import 'binary_sources.dart';
import 'categories.dart';
import 'catalog_context.dart';
import 'catalog_api.dart';
import 'catalog_state.dart' show catalogManifest;
import 'dolphin_registry.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'models/detail.dart';
import 'models/manifest.dart';
import 'models/plan.dart';
import '../../../services/logging.dart';
import '../../../services/telemetry/traced.dart';
import '../../../services/dolphin/library.dart';
import '../../../services/dolphin/manifest_editor.dart';
import '../../../components/codec/dolphin/manifest.dart';

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
    required this.source,
    required this.onInstalled,
    DolphinRegistry? dolphin,
    DolphinManifestEditor? dolphinManifest,
    ManifestRegistry? styleManifests,
  }) : dolphin = dolphin ?? DolphinRegistry(client: client),
       dolphinManifest =
           dolphinManifest ?? DolphinManifestEditor(client: client),
       styleManifests =
           styleManifests ??
           ManifestRegistry(
             client: client,
             root: kMenuStyleManifestsRoot,
             cached: false,
           );

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final CatalogContext catalog;
  final AppBinarySource source;
  final DolphinRegistry dolphin;
  final DolphinManifestEditor dolphinManifest;
  final ManifestRegistry styleManifests;

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
    // A card made for one entry is installed when that app's file is.
    if (app.selectedAppId == null &&
        app.id.isNotEmpty &&
        manifests.byUid(app.id) != null) {
      return true;
    }
    return app.alias.isNotEmpty && manifests.byAlias(app.alias) != null;
  }

  final List<_AppTask> _taskQueue = [];
  final Map<String, _PreparedInstall> _preparedInstalls = {};
  final Map<String, _PreparedAnimation> _preparedAnimations = {};
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
    unawaited(guarded('[InstallEngine] drain task queue', _drainTaskQueue));
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
          // Every queued task is device work, and this is where it starts, so
          // this is where it binds: the frames it sends, the pings that pace
          // them and the cleanup that follows a cancelled one all keep going to
          // the Flipper it began against, however many the user swaps in
          // meanwhile. What it may then write into the registries is a separate
          // question, and the scope token answers that one.
          ok = await client.runTask(
            FlipperRequestPriority.background,
            task.run,
          );
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
            _forgetPrepared(task.alias);
            if (_clearAction(task.alias)) notifyListeners();
          }
        } on FlipperWriteCancelledException {
          _forgetPrepared(task.alias);
          if (_clearAction(task.alias)) notifyListeners();
        } on _DeviceChangedException {
          // Not a failure: the task reached the device it was for, and the
          // registries describe a different one now. handleReset has already
          // emptied the queue and the action map; this only keeps the task from
          // reporting itself into a Flipper that never asked for it.
          _forgetPrepared(task.alias);
          // LogService.info(
          //   '[InstallEngine] task "${task.alias}" dropped: device changed',
          // );
          if (_clearAction(task.alias)) notifyListeners();
        } catch (e) {
          // Install and uninstall each catch their own and end at
          // _failAction, so what reaches here is restore - one tap, not a
          // batch. The bool handed to task.done is discarded by every caller
          // but one, and a corrupted upload arrives as a StateError this
          // engine raised itself, which flipperlib never saw.
          LogService.warn('[InstallEngine] task "${task.alias}" failed: $e');
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

  void _forgetPrepared(String alias) {
    _preparedInstalls.remove(alias);
    _preparedAnimations.remove(alias);
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
      _forgetPrepared(alias);
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

  /// The device-switch counterpart of [_throwIfCancelled].
  ///
  /// A running task cannot be torn out from under the device any more than a
  /// cancelled one can, so it unwinds at its next checkpoint instead. The
  /// checkpoints sit before the device writes and before the registry writes:
  /// what has already reached the previous Flipper is correct there, and what
  /// has not must not be aimed at the one attached now.
  void _throwIfStale(DeviceToken token) {
    if (token.isStale) throw const _DeviceChangedException();
  }

  /// Timed as one operation — ADR 0013 §2 names app install.
  ///
  /// Timed from **outside** `_enqueueTask`, so the span covers the wait in the
  /// queue as well as the install. Installing three apps at once is exactly
  /// the case where the two differ, and the user is waiting for both.
  ///
  /// `traced` goes after the two early returns: neither is an install, and
  /// recording them would put nil-duration operations around every real one.
  ///
  /// The alias is **not** attached. It names a third-party app the user chose
  /// to install, which is a fact about them rather than about the app, and no
  /// pattern in `Scrub` recognises one. `update` against `install` is the
  /// distinction worth having, because an update also has to remove what was
  /// there.
  Future<bool> installOrUpdate(
    AppCard app, {
    AppCategory? category,
    AppDetail? detail,
  }) {
    if (!isReady || app.alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(app.alias)) return Future.value(false);
    _failures.remove(app.alias);

    final wasInstalled = isInstalled(app);
    _actions[app.alias] = AppAction(
      alias: app.alias,
      type: wasInstalled ? AppActionType.update : AppActionType.install,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return traced('app.install', (trace) async {
      trace.note('update', wasInstalled);
      final ok = await _enqueueTask(
        app.alias,
        () => _performInstall(app, category: category, detail: detail),
      );
      // `_performInstall` reports a failure by answering false, so without
      // this every refused install would arrive as a successful operation.
      if (!ok) trace.failed();
      return ok;
    });
  }

  Future<bool> _performInstall(
    AppCard app, {
    AppCategory? category,
    AppDetail? detail,
  }) async {
    if (!_actions.containsKey(app.alias)) return false;
    final token = client.deviceToken;

    try {
      var prepared = _preparedInstalls[app.alias];
      if (prepared == null) {
        _setActionState(app.alias, stage: AppActionStage.download, progress: 0);
        if ((api.target == null || api.api == null) && !isReady) {
          throw const _LinkDroppedException();
        }
        await catalog.ensureDeviceFilters(required: true);
        _throwIfCancelled(app.alias);

        var cv = detail?.card.currentVersion ?? app.currentVersion;
        if (cv == null || cv.id.isEmpty || cv.currentBuild == null) {
          final fetched = await api.fetchApp(app.alias, family: _familyOf(app));
          cv = fetched.card.currentVersion;
        }
        if (cv == null || cv.id.isEmpty || cv.currentBuild == null) {
          throw StateError(l10n.appsErrorNoVersion);
        }

        final existingManifest = manifests.byAlias(app.alias);
        final fapPath = await _binaryPath(
          app,
          category: category,
          manifest: existingManifest,
        );
        final previousPath = existingManifest?.path ?? '';
        if (previousPath.isNotEmpty && previousPath != fapPath) {
          LogService.info(
            '[InstallEngine] ${app.alias} moves from $previousPath to $fapPath',
          );
        }

        // What the catalog says it is, read before the download: a status
        // that cannot be read fails the install before anything is fetched.
        // It is cached, so this costs no request after the first.
        final devCatalog = await api.fetchDevCatalog();
        _throwIfCancelled(app.alias);

        Future<BuiltFile> fetch(AppCurrentVersion version) => source.fetch(
          app,
          version: version,
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

        BuiltFile fetched;
        try {
          fetched = await fetch(cv);
        } on CatalogVersionGoneException {
          cv = await _replacing(app, cv);
          fetched = await fetch(cv);
        }
        _throwIfCancelled(app.alias);
        _setActionState(app.alias, stage: AppActionStage.download, progress: 1);
        final fapBytes = fetched.bytes;

        final manifest = _manifestFor(
          app,
          cv,
          path: fapPath,
          buildApi: fetched.buildApi,
          devCatalog: devCatalog,
          icon: await source.iconBase64(app, cv),
        );

        unawaited(
          guarded(
            '[InstallEngine] cache icon',
            () => _cacheFapIcon(app.alias, fapBytes),
          ),
        );

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
      await _ensureDirs(installDir);
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
      _throwIfStale(token);
      manifests.put(app.alias, manifest);
      // The installed-apps mirror walks the apps root and keeps .fap copies;
      // a terminal plugin is neither, and is tracked by its manifest alone.
      if (fapPath.startsWith('$kAppsRoot/')) {
        await onInstalled(
          alias: app.alias,
          devicePath: fapPath,
          fapBytes: prepared.fapBytes,
        );
      }
      _preparedInstalls.remove(app.alias);
      _clearAction(app.alias);
      notifyListeners();
      return true;
    } catch (e) {
      if (e is _DeviceChangedException) rethrow;
      if (_cancelling.contains(app.alias)) {
        _preparedInstalls.remove(app.alias);
        // Not a failure: the user asked for this.
        LogService.info('[InstallEngine] install ${app.alias} cancelled');
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

  Future<bool> installMenuStyle(AppCard app) {
    if (!isReady || app.alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(app.alias)) return Future.value(false);
    _failures.remove(app.alias);
    final wasInstalled =
        styleManifests.byUid(app.id) != null ||
        styleManifests.byAlias(app.alias) != null;
    _actions[app.alias] = AppAction(
      alias: app.alias,
      type: wasInstalled ? AppActionType.update : AppActionType.install,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(app.alias, () => _performMenuStyleInstall(app));
  }

  Future<bool> _performMenuStyleInstall(AppCard app) async {
    if (!_actions.containsKey(app.alias)) return false;
    final token = client.deviceToken;
    try {
      _setActionState(app.alias, stage: AppActionStage.download, progress: 0);
      if ((api.target == null || api.api == null) && !isReady) {
        throw const _LinkDroppedException();
      }
      await catalog.ensureDeviceFilters(required: true);
      _throwIfCancelled(app.alias);
      final cv = app.currentVersion;
      if (cv == null || cv.id.isEmpty) {
        throw StateError(l10n.appsErrorNoVersion);
      }
      final fileName = '${app.alias}.fal';
      if (!fileName.startsWith(kMenuStylePrefix) ||
          fileName.length >= kMenuStyleNameLimit) {
        throw StateError(
          '"$fileName" is not a name the firmware lists as a menu style',
        );
      }

      void report(int received, int? total) {
        _throwIfCancelled(app.alias);
        if (total == null || total <= 0) return;
        _setActionState(
          app.alias,
          stage: AppActionStage.download,
          progress: received / total,
        );
      }

      final devCatalog = await api.fetchDevCatalog();
      _throwIfCancelled(app.alias);

      Future<bool> install(AppCurrentVersion cv) async {
        final BuiltFile fal;
        try {
          fal = await api.fetchMenuStyleBuild(cv.id, onProgress: report);
        } on AppHttpException catch (e) {
          if (e.statusCode != 404) rethrow;
          final styleApi = cv.currentBuild?.sdk?.api ?? '';
          final canFallback = styleApi.isNotEmpty && styleApi != api.api;
          if (!canFallback || !catalog.apiFallbackEnabled) {
            throw StateError(
              canFallback
                  ? l10n.appsErrorApiMismatch(styleApi, api.api ?? '?')
                  : l10n.appsErrorNoBuild(api.api ?? '?'),
            );
          }
          final fallback = await api.fetchMenuStyleBuild(
            cv.id,
            onProgress: report,
            apiOverride: styleApi,
          );
          return await _writeMenuStyle(app, cv, fallback, devCatalog, token);
        }
        return await _writeMenuStyle(app, cv, fal, devCatalog, token);
      }

      try {
        return await install(cv);
      } on CatalogVersionGoneException {
        return await install(await _replacing(app, cv));
      }
    } catch (e) {
      if (e is _DeviceChangedException) rethrow;
      if (_cancelling.contains(app.alias)) {
        // Not a failure: the user asked for this.
        LogService.info('[InstallEngine] menu style ${app.alias} cancelled');
        _clearAction(app.alias);
        notifyListeners();
        return false;
      }
      if (e is _LinkDroppedException || !isReady) {
        _setActionState(app.alias, stage: AppActionStage.queued, progress: 0);
        throw const _LinkDroppedException();
      }
      return _failAction(app.alias, e, 'install menu style');
    }
  }

  Future<bool> _writeMenuStyle(
    AppCard app,
    AppCurrentVersion cv,
    BuiltFile built,
    bool devCatalog,
    DeviceToken token,
  ) async {
    _throwIfCancelled(app.alias);
    if (!isReady) throw const _LinkDroppedException();
    _throwIfStale(token);

    final falPath = '$kMenuStylesRoot/${app.alias}.fal';
    final fimPath = '$kMenuStyleManifestsRoot/${app.alias}.fim';
    final fal = built.bytes;
    final manifest = _manifestFor(
      app,
      cv,
      path: falPath,
      buildApi: built.buildApi,
      devCatalog: devCatalog,
      icon: await source.iconBase64(app, cv),
    );
    final manifestBytes = utf8.encode(manifest.encode());

    final loader = kMenuStylesRoot.substring(
      0,
      kMenuStylesRoot.lastIndexOf('/'),
    );
    await _ensureDir(loader.substring(0, loader.lastIndexOf('/')));
    await _ensureDir(loader);
    await _ensureDir(kMenuStylesRoot);
    await _ensureDir(kMenuStyleManifestsRoot);

    await client.storageWriteChunked(
      falPath,
      fal,
      onProgress: (p) =>
          _setActionState(app.alias, stage: AppActionStage.upload, progress: p),
      isCancelled: () => _cancelling.contains(app.alias),
    );
    _setActionState(app.alias, stage: AppActionStage.check, progress: 1);
    await _verifyUpload(falPath, fal);
    await client.storageWriteChunked(fimPath, manifestBytes);
    await _verifyUpload(fimPath, manifestBytes);

    _throwIfStale(token);
    styleManifests.put(app.alias, manifest);
    _clearAction(app.alias);
    notifyListeners();
    return true;
  }

  Future<bool> installAnimation(AppCard app) {
    if (app.alias.isEmpty) return Future.value(false);
    if (_actions.containsKey(app.alias)) return Future.value(false);
    _failures.remove(app.alias);
    final toDevice = isReady;
    _actions[app.alias] = AppAction(
      alias: app.alias,
      type: dolphin.contains(app.alias)
          ? AppActionType.update
          : AppActionType.install,
      stage: AppActionStage.queued,
    );
    notifyListeners();
    return _enqueueTask(
      app.alias,
      () => _performAnimationInstall(app, toDevice: toDevice),
    );
  }

  Future<bool> _performAnimationInstall(
    AppCard app, {
    required bool toDevice,
  }) async {
    if (!_actions.containsKey(app.alias)) return false;
    final token = client.deviceToken;
    try {
      var prepared = _preparedAnimations[app.alias];
      if (prepared == null) {
        _setActionState(app.alias, stage: AppActionStage.download, progress: 0);
        final versionId = app.currentVersion?.id ?? '';
        if (versionId.isEmpty) throw StateError(l10n.appsErrorNoVersion);
        final plan = await api.fetchAnimationPlan(versionId);
        final entry = plan.entry;
        if (plan.files.isEmpty || entry == null || entry.name.isEmpty) {
          throw StateError('Install plan of "${app.alias}" is empty');
        }

        final total = plan.files.fold<int>(0, (sum, f) => sum + f.size);
        var received = 0;
        final downloaded = <(PlanFile, List<int>)>[];
        for (final file in plan.files) {
          _throwIfCancelled(app.alias);
          final bytes = await api.fetchPlanFile(file.uri);
          final digest = sha256.convert(bytes).toString();
          if (file.sha256.isNotEmpty && digest != file.sha256) {
            throw StateError(
              '"${file.devicePath}" sha256 $digest, expected ${file.sha256}',
            );
          }
          downloaded.add((file, bytes));
          received += bytes.length;
          if (total > 0) {
            _setActionState(
              app.alias,
              stage: AppActionStage.download,
              progress: received / total,
            );
          }
        }

        _throwIfCancelled(app.alias);
        for (final (file, bytes) in downloaded) {
          await saveToDolphinLibrary(file.devicePath, bytes);
        }
        prepared = _PreparedAnimation(
          entry: ManifestEntry(
            name: entry.name,
            selected: true,
            minButthurt: entry.minButthurt ?? ManifestEntry.kDefaultMinButthurt,
            maxButthurt: entry.maxButthurt ?? ManifestEntry.kDefaultMaxButthurt,
            minLevel: entry.minLevel ?? ManifestEntry.kDefaultMinLevel,
            maxLevel: entry.maxLevel ?? ManifestEntry.kDefaultMaxLevel,
            weight: entry.weight ?? ManifestEntry.kDefaultWeight,
          ),
          files: downloaded,
        );
        _preparedAnimations[app.alias] = prepared;
      }

      if (toDevice) {
        _throwIfCancelled(app.alias);
        if (!isReady) throw const _LinkDroppedException();
        _throwIfStale(token);

        final dirs = <String>{
          for (final (file, _) in prepared.files)
            file.devicePath.substring(0, file.devicePath.lastIndexOf('/')),
        };
        await _ensureDir(kDolphinRoot);
        for (final dir in dirs) {
          await _ensureDir(dir);
        }

        final total = prepared.files.fold<int>(
          0,
          (sum, f) => sum + f.$2.length,
        );
        var written = 0;
        for (final (file, bytes) in prepared.files) {
          final before = written;
          await client.storageWriteChunked(
            file.devicePath,
            bytes,
            onProgress: (p) => _setActionState(
              app.alias,
              stage: AppActionStage.upload,
              progress: total > 0 ? (before + p * bytes.length) / total : p,
            ),
            isCancelled: () => _cancelling.contains(app.alias),
          );
          await _verifyUpload(file.devicePath, bytes);
          written += bytes.length;
        }

        _setActionState(app.alias, stage: AppActionStage.check, progress: 1);
        final manifest = prepared.manifest ??= await dolphinManifest.edit(
          prepared.entry,
        );
        _throwIfStale(token);
        await dolphinManifest.write(manifest);

        _throwIfStale(token);
        dolphin.put(prepared.entry.name);
      }
      _preparedAnimations.remove(app.alias);
      _clearAction(app.alias);
      notifyListeners();
      return true;
    } catch (e) {
      if (e is _DeviceChangedException) rethrow;
      if (_cancelling.contains(app.alias)) {
        _preparedAnimations.remove(app.alias);
        // Not a failure: the user asked for this.
        LogService.info('[InstallEngine] animation ${app.alias} cancelled');
        _clearAction(app.alias);
        notifyListeners();
        return false;
      }
      if (e is _LinkDroppedException || (toDevice && !isReady)) {
        _setActionState(app.alias, stage: AppActionStage.queued, progress: 0);
        throw const _LinkDroppedException();
      }
      _preparedAnimations.remove(app.alias);
      return _failAction(app.alias, e, 'install animation');
    }
  }

  Future<bool> _failAction(String alias, Object error, String what) async {
    // The fan-in for an install or uninstall that failed with the link up.
    // Link drops are rethrown past this to be requeued, and restore has no
    // catch of its own and fails through the queue worker instead. The cause
    // stops here.
    LogService.warn('[InstallEngine] $what $alias failed: $error');
    _failures[alias] = error;
    await Future<void>.delayed(const Duration(seconds: 2));
    _clearAction(alias);
    notifyListeners();
    return false;
  }

  final Map<String, Object> _failures = {};

  Object? takeFailure(String alias) => _failures.remove(alias);

  Future<bool> uninstall(AppCard app, {AppCategory? category}) =>
      _enqueueDelete(
        app.alias,
        () async =>
            manifests.byAlias(app.alias)?.path ??
            await _binaryPath(app, category: category),
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
    final token = client.deviceToken;
    _setActionState(alias, stage: AppActionStage.download);
    try {
      final fapPath = await resolveFapPath();
      _throwIfStale(token);
      await _safeDelete('$kManifestsRoot/$alias.fim');
      await _safeDelete(fapPath);
      _throwIfStale(token);
      manifests.removeAlias(alias);
      _clearAction(alias);
      notifyListeners();
      return true;
    } catch (e) {
      if (e is _DeviceChangedException) rethrow;
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
          await _binaryPath(app, category: category),
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
      final token = client.deviceToken;
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
        _throwIfStale(token);
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
      // Returns as though verified. A mismatch throws below, but being unable
      // to ask is indistinguishable to every caller from having asked and been
      // satisfied - so the install reports success and only this says
      // otherwise.
      LogService.warn('[InstallEngine] md5 of "$path" unavailable: $e');
      return;
    }
    if (actual.isEmpty) {
      // Same as above: no checksum to compare, so the upload goes unverified
      // and reports success.
      LogService.warn('[InstallEngine] md5 of "$path" came back empty');
      return;
    }
    if (actual != expected) {
      throw StateError(
        'Uploaded "$path" is corrupted: md5 $actual, expected $expected',
      );
    }
    LogService.info('[InstallEngine] md5 of "$path" verified');
  }

  Future<void> _ensureDir(String path) async {
    try {
      await client.storageMkdir(MkdirRequest(path: path));
    } catch (_) {}
  }

  Future<void> _safeDelete(String path) async {
    try {
      await client.storageDelete(DeleteRequest(path: path, recursive: false));
    } catch (e) {
      // Best-effort on purpose: the caller carries on and reports success
      // either way, because the file may already be gone and stopping here
      // would leave an app half-installed or half-removed. What is left is a
      // file on the SD card the app believes it has deleted.
      LogService.warn('[InstallEngine] could not remove "$path": $e');
    }
  }

  /// Creates [path] and every folder above it below `/ext`: storage mkdir
  /// makes one level, and `/ext/apps_data/cli` is not there on a fresh card.
  Future<void> _ensureDirs(String path) async {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    for (var i = 2; i <= parts.length; i++) {
      await _ensureDir('/${parts.sublist(0, i).join('/')}');
    }
  }

  /// The version that took [gone]'s place in the catalog since [app]'s card
  /// was read: its card read again, not the copy kept. One that names no
  /// other version, or none with a build, is the error it was.
  Future<AppCurrentVersion> _replacing(
    AppCard app,
    AppCurrentVersion gone,
  ) async {
    final detail = await api.fetchApp(
      app.alias,
      family: _familyOf(app),
      app: app.selectedAppId,
      fresh: true,
    );
    _throwIfCancelled(app.alias);
    final current = detail.card.currentVersion;
    if (current == null ||
        current.id.isEmpty ||
        current.id == gone.id ||
        current.currentBuild == null) {
      throw CatalogVersionGoneException(gone.id);
    }
    LogService.info(
      '[InstallEngine] ${app.alias}: ${gone.id} is gone, '
      'installing ${current.id} (${current.version})',
    );
    return current;
  }

  /// The `.fim` an install from the catalog writes (models/manifest.dart).
  AppManifest _manifestFor(
    AppCard app,
    AppCurrentVersion cv, {
    required String path,
    required String? buildApi,
    required bool devCatalog,
    required String? icon,
  }) => catalogManifest(
    card: app,
    version: cv,
    path: path,
    buildApi: buildApi,
    devCatalog: devCatalog,
    icon: icon,
    server: api.server,
  );

  static CatalogFamily _familyOf(AppCard app) =>
      CatalogFamily.byServerName(app.family) ?? CatalogFamily.apps;

  /// Where an app's binary lives on the SD card: a terminal plugin as a
  /// `.fal` under [kCliPluginsRoot], everything else as a `.fap` under the
  /// apps root.
  Future<String> _binaryPath(
    AppCard app, {
    AppCategory? category,
    AppManifest? manifest,
  }) async {
    if (_familyOf(app) == CatalogFamily.cli) {
      return '${_cliInstallDir(app)}/${app.alias}.fal';
    }
    final dir = await _resolveInstallDir(
      app,
      category: category,
      manifest: manifest,
    );
    return '$dir/${app.alias}.fap';
  }

  /// The catalogue's `install_path` for a CLI app, held to the plugin root:
  /// the terminal looks nowhere else, and a path out of it is not ours to
  /// write.
  String _cliInstallDir(AppCard app) {
    final raw = app.installPath?.trim() ?? '';
    if (raw.isEmpty || raw == kCliPluginsRoot) return kCliPluginsRoot;
    final relative = raw.startsWith('$kCliPluginsRoot/')
        ? raw.substring(kCliPluginsRoot.length + 1)
        : null;
    final valid =
        relative != null &&
        relative.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
    if (!valid) {
      LogService.warn(
        '[InstallEngine] ${app.alias}: install_path "$raw" is outside '
        '$kCliPluginsRoot, ignored',
      );
      return kCliPluginsRoot;
    }
    return '$kCliPluginsRoot/$relative';
  }

  Future<String> _resolveInstallDir(
    AppCard app, {
    AppCategory? category,
    AppManifest? manifest,
  }) async {
    final fromCatalog = _catalogInstallDir(app);
    if (fromCatalog != null) return fromCatalog;
    final manifestPath = manifest?.path ?? manifests.byAlias(app.alias)?.path;
    if (manifestPath != null && manifestPath.isNotEmpty) {
      final lastSlash = manifestPath.lastIndexOf('/');
      if (lastSlash > 0) return manifestPath.substring(0, lastSlash);
    }
    final categoryAlias = await _resolveCategoryAlias(category, app.categoryId);
    return '$kAppsRoot/$categoryAlias';
  }

  String? _catalogInstallDir(AppCard app) {
    final raw = app.installPath?.trim() ?? '';
    if (raw.isEmpty) return null;
    final relative = raw.startsWith('$kAppsRoot/')
        ? raw.substring(kAppsRoot.length + 1)
        : raw;
    final segments = relative.split('/');
    final valid =
        !relative.startsWith('/') &&
        segments.every((s) => s.isNotEmpty && s != '.' && s != '..');
    if (!valid) {
      LogService.warn(
        '[InstallEngine] ${app.alias}: install_path "$raw" is outside '
        '$kAppsRoot, ignored',
      );
      return null;
    }
    return '$kAppsRoot/$relative';
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
      // The fallback is the catalog UID, and _resolveInstallDir turns it
      // into a directory - so the app lands in /ext/apps/<hex uid>/ and the
      // manifest records that path, which later installs then prefer.
      LogService.warn(
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
    _preparedAnimations.clear();
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
    unawaited(guarded('[InstallEngine] drain task queue', _drainTaskQueue));
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

class _PreparedAnimation {
  _PreparedAnimation({required this.entry, required this.files});

  final ManifestEntry entry;
  final List<(PlanFile, List<int>)> files;
  String? manifest;
}

class _LinkDroppedException implements Exception {
  const _LinkDroppedException();
}

/// Raised at a checkpoint when the Flipper in scope changed under a task.
class _DeviceChangedException implements Exception {
  const _DeviceChangedException();
}

class _CancelledException implements Exception {
  const _CancelledException();
}
