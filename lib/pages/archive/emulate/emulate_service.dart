import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

import '../models/archive_key.dart';

enum EmulateError {
  notConnected,
  notEmulatable,
  appStartFailed,
  loadFileFailed,
}

class EmulateResult {
  EmulateResult.ok() : error = null;
  EmulateResult.fail(EmulateError this.error);
  final EmulateError? error;
  bool get isOk => error == null;
}

class EmulateService {
  EmulateService({FlipperClient? client}) : _client = client ?? FlipperOneClient().get();

  final FlipperClient _client;
  bool _running = false;
  ArchiveKey? _activeKey;

  bool get isRunning => _running;
  ArchiveKey? get activeKey => _activeKey;

  Future<EmulateResult> start(ArchiveKey key) async {
    if (!_client.isConnected) return EmulateResult.fail(EmulateError.notConnected);
    final appName = key.category.flipperAppName;
    if (appName == null) return EmulateResult.fail(EmulateError.notEmulatable);

    if (_running) {
      await stop();
    }

    try {
      await _client.appStart(
        StartRequest(name: appName, args: 'RPC'),
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      LogService.log('[Emulate] appStart failed: $e');
      return EmulateResult.fail(EmulateError.appStartFailed);
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));

    try {
      await _client.appLoadFile(
        AppLoadFileRequest(path: key.remotePath),
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      LogService.log('[Emulate] appLoadFile failed: $e');
      await _safeExit();
      return EmulateResult.fail(EmulateError.loadFileFailed);
    }

    _running = true;
    _activeKey = key;
    return EmulateResult.ok();
  }

  Future<void> stop() async {
    if (!_running) return;
    await _safeExit();
    _running = false;
    _activeKey = null;
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
