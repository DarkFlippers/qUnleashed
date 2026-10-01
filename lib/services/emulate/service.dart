import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import '../../components/archive/models/key.dart';
import '../../components/archive/parser.dart';
import '../guarded.dart';
import '../logging.dart';

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
  /// [client] is the Flipper the emulation opens on.
  ///
  /// Required: both builders have one - the emulate page takes it from the
  /// scope its pusher was in, the home-screen widget from the composition
  /// root - and a default would only hide which device a run belongs to,
  /// which is the one thing this class is careful about. ADR 0002.
  EmulateService({required this._client});

  final FlipperClient _client;
  bool _running = false;
  ArchiveKey? _activeKey;
  Future<void>? _stopFuture;

  /// The Flipper the emulation is open on, held from start to stop.
  ///
  /// An emulation belongs to the window the user tapped, so it lives only while
  /// that Flipper is the one in front of them; [_onConnection] closes it the
  /// moment another takes its place. Held rather than looked up per call
  /// precisely so that closing it lands where the scene is: by then the switch
  /// has happened, and a second appExit on a Flipper with no scene open is a
  /// firmware check failure.
  FlipperSessionBinding? _binding;

  StreamSubscription<FlipperConnectionState>? _connection;

  Future<void> _btnChain = Future<void>.value();
  bool _txHeld = false;
  bool _sceneLoaded = false;

  bool get isRunning => _running;
  ArchiveKey? get activeKey => _activeKey;

  Future<EmulateResult> start(ArchiveKey key) async {
    if (!_client.isConnected) {
      return EmulateResult.fail(EmulateError.notConnected);
    }
    // Ahead of the binding, deliberately: a run still open belongs to the
    // Flipper it was started on, and closing it is that binding's job, not the
    // new one's.
    if (_running || _stopFuture != null) await stop();

    final binding = _client.bindCurrentSession();
    _binding = binding;
    _connection ??= _client.connectionStream.listen(_onConnection);
    return binding.run(() => _start(key));
  }

  Future<EmulateResult> _start(ArchiveKey key) async {
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
        StartRequest(name: appName, args: 'RPC'),
        timeout: const Duration(seconds: 10),
      );
    } on FlipperRpcAppSystemLockedException {
      return EmulateResult.fail(EmulateError.busy);
    } on FlipperRpcBusyException {
      return EmulateResult.fail(EmulateError.busy);
    } catch (e) {
      // The fail below is the surface, and it carries a category rather
      // than a cause: the page renders "could not open the app" for it, the
      // same words for a firmware that refused and a link that went. This is
      // the only place the difference exists.
      LogService.warn('[Emulate] appStart failed: $e');
      return EmulateResult.fail(EmulateError.appStartFailed);
    }

    final ready = await started;
    if (!ready) {
      LogService.info(
        '[Emulate] APP_STARTED not seen, proceeding after fallback',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    try {
      await _client.appLoadFile(
        AppLoadFileRequest(path: key.remotePath),
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      // As above: loadFileFailed renders one message for every way a file
      // can fail to load.
      LogService.warn('[Emulate] appLoadFile failed: $e');
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
    if (!_client.isConnected) {
      return EmulateResult.fail(EmulateError.notConnected);
    }

    final appName = key.category.flipperAppName;
    if (appName == null) return EmulateResult.fail(EmulateError.notEmulatable);

    try {
      await _client.appStart(
        StartRequest(name: appName, args: key.remotePath),
        timeout: const Duration(seconds: 10),
      );
    } on FlipperRpcAppSystemLockedException {
      return EmulateResult.fail(EmulateError.busy);
    } on FlipperRpcBusyException {
      return EmulateResult.fail(EmulateError.busy);
    } catch (e) {
      // As above, on the path that opens an app for the user to drive.
      LogService.warn('[Emulate] launchApp appStart failed: $e');
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
      // Not a failure the caller treats as one: a null protocol resolves to
      // a different launch method, so the button quietly does something other
      // than what the file asks for.
      LogService.warn('[Emulate] could not read the protocol: $e');
      return null;
    }
  }

  /// Keys the transmitter. Tells whether it is keyed when the future ends.
  ///
  /// False is a press the Flipper never took: the five-second RPC timeout
  /// over a link that has gone is the ordinary way, and the scene failing to
  /// reload before it is the other. The caller cannot see either from the
  /// log, and the home-screen widget flashed "sent" for both. #104.
  Future<bool> sendPress() {
    return _enqueueButton(
      'button press',
      () => _onDevice(() async {
        // Already keyed, so the press the caller asked for is in effect.
        if (_txHeld) return true;
        if (!_sceneLoaded) {
          if (!await _reloadForSend()) return false;
        }
        await _client.appButtonPress(
          AppButtonPressRequest(),
          timeout: const Duration(seconds: 5),
        );
        _txHeld = true;
        return true;
      }),
    );
  }

  /// Unkeys the transmitter. Tells whether it is unkeyed when the future ends.
  Future<bool> sendRelease() {
    return _enqueueButton(
      'button release',
      () => _onDevice(() async {
        // Nothing keyed, so there is nothing to release and nothing failed.
        if (!_txHeld) return true;
        _txHeld = false;
        await _client.appButtonRelease(
          AppButtonReleaseRequest(),
          timeout: const Duration(seconds: 5),
        );
        _sceneLoaded = false;
        return true;
      }),
    );
  }

  /// Runs [body] against the Flipper the emulation is open on.
  ///
  /// Falls back to the active session only when nothing is open, which is the
  /// case for the calls that do not belong to a run - fetching a protocol, or
  /// launching an app the user then drives themselves afterwards.
  Future<T> _onDevice<T>(Future<T> Function() body) {
    final binding = _binding;
    return binding == null ? body() : binding.run(body);
  }

  void _onConnection(FlipperConnectionState state) {
    // Gone from the screen means gone: an emulation is the window the user
    // tapped, and the Flipper they have moved on from should not be left
    // holding it open with nothing driving it. The link simply dropping is not
    // this - it comes back, and the scene with it.
    if (state.event == FlipperConnectionEvent.deviceChanged) {
      unawaited(stop());
    }
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
        // Per attempt, and there are four of them in under a second - the
        // tally below is what says the run gave up.
        LogService.info(
          '[Emulate] reload before send failed (try $attempt): $e',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    // Four tries and the scene is still not on the device, so the press that
    // follows is never sent. Nothing on screen says so - the button behaves
    // as it always does, which is #104 - and the lines above do not survive a
    // release build, so without this the one failure the user can feel leaves
    // no record anywhere.
    LogService.warn('[Emulate] gave up reloading "${key.remotePath}" to send');
    return false;
  }

  /// Queues [op] behind whatever button command is already in flight.
  ///
  /// [what] names it because press and release fail the same way - a five
  /// second RPC timeout over a link that has gone - and an entry saying only
  /// "button command" cannot be told apart from its neighbour.
  ///
  /// The predecessor is awaited inside guarded rather than chained ahead of it,
  /// so the future stored in _btnChain cannot reject and a failed command
  /// cannot strand the ones behind it.
  ///
  /// The outcome reaches the caller through a flag rather than the future,
  /// for that reason: [guarded] swallows the throw by contract, and the
  /// returned future is `next.then(...)`, which inherits never rejecting.
  /// A run that never happened - the queue drained after stop() - reports
  /// false, because nothing reached the Flipper either way.
  Future<bool> _enqueueButton(String what, Future<bool> Function() op) {
    final previous = _btnChain;
    // False until the operation says otherwise, which covers both ways it
    // can fail to reach the Flipper: a throw, which guarded swallows before
    // the assignment happens, and a run that never started because stop()
    // emptied the chain while this was queued. No onFailure hook for that
    // reason - it would only assign what is already there.
    var sent = false;
    final next = guarded('[Emulate] $what', () async {
      await previous;
      // Read after the wait, not before: stop() clears it while this is
      // queued, and a press that ran anyway would leave the transmitter
      // keyed with no release behind it.
      if (_running) sent = await op();
    });
    _btnChain = next;
    return next.then((_) => sent);
  }

  Future<void> stop() {
    return _stopFuture ??= _doStop();
  }

  Future<void> _doStop() => _onDevice(_doStopOnDevice);

  Future<void> _doStopOnDevice() async {
    try {
      if (!_running) return;
      _running = false;
      _txHeld = false;
      _sceneLoaded = false;

      // The handler goes on at creation, not at the await below. `_safeExit`
      // sits between the two and spans event-loop turns, and a future that
      // rejects while nothing is listening is reported unhandled there and
      // then - attaching a catch afterwards is too late. The sibling in
      // `_start` has always done it this way. #23
      final closed = _client
          .appStateStream()
          .firstWhere((s) => s.state == AppState.APP_CLOSED)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => AppStateResponse(state: AppState.APP_CLOSED),
          )
          .catchError((Object e) {
            // Stays at info: the five-second timeout above answers the case
            // this is here for - a device that simply does not say it closed -
            // by returning APP_CLOSED itself. What reaches here is the state
            // stream erroring, which the client reports where it happens.
            LogService.info('[Emulate] wait APP_CLOSED failed: $e');
            return AppStateResponse(state: AppState.APP_CLOSED);
          });

      await _safeExit();
      await closed;

      _activeKey = null;
    } finally {
      _binding = null;
      unawaited(_connection?.cancel());
      _connection = null;
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
      // The app is left running on the Flipper, and the next emulate the
      // user starts comes back "device busy" - a symptom one step removed
      // from its cause, with nothing connecting the two.
      LogService.warn('[Emulate] appExit failed: $e');
    }
  }
}
