import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import '../models/key.dart';
import '../overview/metadata/parser.dart';

enum EmulateError {
  notConnected,
  notEmulatable,
  appStartFailed,
  loadFileFailed,
  busy,
}

class EmulateResult {
  EmulateResult.ok() : error = null;
  EmulateResult.fail(EmulateError this.error);
  final EmulateError? error;
  bool get isOk => error == null;
}

class EmulateService {
  EmulateService({FlipperClient? client})
      : _client = client ?? FlipperOneClient().get();

  final FlipperClient _client;
  bool _running = false;
  ArchiveKey? _activeKey;
  Future<void>? _stopFuture;

  Future<void> _btnChain = Future<void>.value();
  bool _txHeld = false;
  bool _sceneLoaded = false;

  bool get isRunning => _running;
  ArchiveKey? get activeKey => _activeKey;

  Future<EmulateResult> start(ArchiveKey key) async {
    if (!_client.isConnected) return EmulateResult.fail(EmulateError.notConnected);
    if (_running || _stopFuture != null) await stop();

    final appName = key.category.flipperAppName;
    if (appName == null) return EmulateResult.fail(EmulateError.notEmulatable);

    final started = _client
        .appStateStream()
        .firstWhere((s) => s.state == AppState.APP_STARTED)
        .then<bool>((_) => true)
        .timeout(const Duration(seconds: 10), onTimeout: () => false)
        .catchError((_) => false);

    try {
      await _client.appStart(
        StartRequest(
          name: appName,
          args: 'RPC',
        ),
        timeout: const Duration(seconds: 10),
      );
    } on FlipperRpcAppSystemLockedException {
      return EmulateResult.fail(EmulateError.busy);
    } on FlipperRpcBusyException {
      return EmulateResult.fail(EmulateError.busy);
    } catch (e) {
      LogService.log('[Emulate] appStart failed: $e');
      return EmulateResult.fail(EmulateError.appStartFailed);
    }

    final ready = await started;
    if (!ready) {
      LogService.log('[Emulate] APP_STARTED not seen, proceeding after fallback');
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    try {
      await _client.appLoadFile(
        AppLoadFileRequest(path: key.remotePath),
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      LogService.log('[Emulate] appLoadFile failed: $e');
      _running = true;
      await stop();
      return EmulateResult.fail(EmulateError.loadFileFailed);
    }

    _running = true;
    _activeKey = key;
    _sceneLoaded = true;
    return EmulateResult.ok();
  }

  Future<EmulateResult> launchApp(ArchiveKey key) async {
    if (!_client.isConnected) return EmulateResult.fail(EmulateError.notConnected);

    final appName = key.category.flipperAppName;
    if (appName == null) return EmulateResult.fail(EmulateError.notEmulatable);

    try {
      await _client.appStart(
        StartRequest(
          name: appName,
          args: key.remotePath,
        ),
        timeout: const Duration(seconds: 10),
      );
    } on FlipperRpcAppSystemLockedException {
      return EmulateResult.fail(EmulateError.busy);
    } on FlipperRpcBusyException {
      return EmulateResult.fail(EmulateError.busy);
    } catch (e) {
      LogService.log('[Emulate] launchApp appStart failed: $e');
      return EmulateResult.fail(EmulateError.appStartFailed);
    }

    return EmulateResult.ok();
  }

  Future<String?> fetchProtocol(ArchiveKey key) async {
    try {
      final bytes = await _client.storageReadChunked(key.remotePath);
      final content = utf8.decode(bytes, allowMalformed: true);
      return parseArchiveKeyMetaContent(key.category, content).protocol;
    } catch (e) {
      LogService.log('[Emulate] fetchProtocol failed: $e');
      return null;
    }
  }

  Future<void> sendPress() {
    return _enqueueButton(() async {
      if (_txHeld) return;
      if (!_sceneLoaded) {
        if (!await _reloadForSend()) return;
      }
      await _client.appButtonPress(
        AppButtonPressRequest(),
        timeout: const Duration(seconds: 5),
      );
      _txHeld = true;
    });
  }

  Future<void> sendRelease() {
    return _enqueueButton(() async {
      if (!_txHeld) return;
      _txHeld = false;
      await _client.appButtonRelease(
        AppButtonReleaseRequest(),
        timeout: const Duration(seconds: 5),
      );
      _sceneLoaded = false;
    });
  }

  Future<bool> _reloadForSend() async {
    final key = _activeKey;
    if (key == null) return false;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _client.appLoadFile(
          AppLoadFileRequest(path: key.remotePath),
          timeout: const Duration(seconds: 10),
        );
        _sceneLoaded = true;
        return true;
      } catch (e) {
        LogService.log('[Emulate] reload before send failed (try $attempt): $e');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }

  Future<void> _enqueueButton(Future<void> Function() op) {
    final next = _btnChain.then((_) async {
      if (!_running) return;
      try {
        await op();
      } catch (e) {
        LogService.log('[Emulate] button command failed: $e');
      }
    });
    _btnChain = next;
    return next;
  }

  Future<void> stop() {
    return _stopFuture ??= _doStop();
  }

  Future<void> _doStop() async {
    try {
      if (!_running) return;
      _running = false;
      _txHeld = false;
      _sceneLoaded = false;

      final closed = _client
          .appStateStream()
          .firstWhere((s) => s.state == AppState.APP_CLOSED)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => AppStateResponse(state: AppState.APP_CLOSED),
          );

      await _safeExit();

      try {
        await closed;
      } catch (e) {
        LogService.log('[Emulate] wait APP_CLOSED failed: $e');
      }

      _activeKey = null;
    } finally {
      _stopFuture = null;
    }
  }

  Future<void> _safeExit() async {
    try {
      await _client.appExit(
        AppExitRequest(),
        timeout: const Duration(seconds: 5),
      );
    } catch (e) {
      LogService.log('[Emulate] appExit failed: $e');
    }
  }
}
