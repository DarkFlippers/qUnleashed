import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime;

import '../../../components/codec/bm.dart';
import '../../../services/connection/device_info_watch.dart';
import '../../../services/logging.dart';

/// Shared virtual-display session for Pixel Draw. Started once when the user
/// enters the manager or the editor and stopped only after both are left.
/// Callers push the latest frame via [pushFrame]; frames are coalesced and sent
/// one at a time only while a device is connected. The editor takes exclusive
/// control via [enterLive]/[leaveLive] and pushes its canvas (debounced to the
/// end of a stroke); the manager mirrors a selected project via [setPreview].
class VirtualDisplaySession {
  VirtualDisplaySession._();

  static final VirtualDisplaySession instance = VirtualDisplaySession._();

  final FlipperClient _client = FlipperOneClient().get();

  /// Hard cap on the device refresh rate, enforced in [_flush] (the send path).
  static const int _minIntervalMs = 1000 ~/ 8; // 8 fps

  StreamSubscription<FlipperConnectionState>? _connSub;

  /// The Flipper the display is up on, held for as long as it is up.
  ///
  /// Every call here is `rightNow`, which orders it ahead of the queue but says
  /// nothing about where it goes. A virtual display is state left switched on
  /// inside one Flipper, and the command that switches it off has to reach that
  /// one - so the session is held from start to stop rather than looked up per
  /// call. Without it a device switch left the first Flipper showing a display
  /// nothing was driving any more, while the stop went to the second.
  FlipperSessionBinding? _binding;
  DeviceToken? _boundTo;

  int _users = 0;
  int _liveHolders = 0;
  bool _active = false;
  bool _starting = false;
  bool _suspended = false;

  Uint8List? _pending;
  bool _sending = false;
  Timer? _sendTimer;
  final Stopwatch _sinceLastSend = Stopwatch();

  List<Uint8List>? _previewFrames;
  int _previewDelayMs = 200;
  int _previewCursor = 0;
  Timer? _previewTimer;

  bool get isActive => _active;

  void enter() {
    _connSub ??= _client.connectionStream.listen(_onConnectionChange);
    _users++;
    if (_users == 1) {
      DeviceInfoWatchService.instance.freeze();
      _ensureStarted();
    }
  }

  void leave() {
    if (_users > 0) _users--;
    if (_users == 0) {
      DeviceInfoWatchService.instance.unfreeze();
      _stop();
    }
  }

  void enterLive() {
    _liveHolders++;
    _stopPreviewTimer();
    enter();
  }

  void leaveLive() {
    if (_liveHolders > 0) _liveHolders--;
    leave();
    if (_liveHolders == 0 && _active && _previewFrames != null) {
      _startPreviewTimer();
    }
  }

  /// Stops the virtual display and pins it off (preview/live pushes are ignored)
  /// until [resume]. Used to free the RPC link for a file transfer to the device
  /// while keeping the holders' ref-counts intact.
  Future<void> suspend() async {
    if (_suspended) return;
    _suspended = true;
    _stopPreviewTimer();
    _pending = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    final wasActive = _active;
    _active = false;
    if (wasActive && _client.isConnected) {
      await _client
          .guiStopVirtualDisplay(priority: FlipperRequestPriority.rightNow)
          .timeout(const Duration(seconds: 2))
          .catchError((_) => <Main>[]);
    }
  }

  /// Lifts a [suspend], restarting the display if anyone still holds it.
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    if (_users > 0) _ensureStarted();
  }

  Future<void> _ensureStarted() async {
    if (_active || _starting || _suspended || !_client.isConnected) return;
    _starting = true;
    final binding = _client.bindCurrentSession();
    _binding = binding;
    _boundTo = _client.deviceToken;
    try {
      await binding.run(() => _start());
    } finally {
      _starting = false;
      if (_active) {
        if (_previewFrames != null &&
            _liveHolders == 0 &&
            _previewTimer == null) {
          _startPreviewTimer();
        }
        _flush();
      }
    }
  }

  Future<void> _start() async {
    try {
      await _client.guiStartVirtualDisplay(
        StartVirtualDisplayRequest(),
        priority: FlipperRequestPriority.rightNow,
      );
      _active = true;
    } on FlipperRpcVirtualDisplayAlreadyStartedException {
      try {
        if (_client.isConnected) {
          await _client.guiStopVirtualDisplay(
            priority: FlipperRequestPriority.rightNow,
          );
        }
        if (_client.isConnected) {
          await _client.guiStartVirtualDisplay(
            StartVirtualDisplayRequest(),
            priority: FlipperRequestPriority.rightNow,
          );
          _active = true;
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _stop() async {
    final binding = _binding;
    _binding = null;
    _boundTo = null;
    _active = false;
    _stopPreviewTimer();
    _previewFrames = null;
    _pending = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    _sinceLastSend
      ..stop()
      ..reset();
    if (binding == null ? !_client.isConnected : !binding.isAlive) return;
    Future<List<Main>> stop() => _client
        .guiStopVirtualDisplay(priority: FlipperRequestPriority.rightNow)
        .timeout(const Duration(seconds: 2))
        .catchError((_) => <Main>[]);
    await (binding == null ? stop() : binding.run(stop));
  }

  void _onConnectionChange(FlipperConnectionState state) {
    if (!state.connected) {
      _active = false;
      _starting = false;
      return;
    }
    // A different Flipper is on screen now. The display follows the user, so it
    // is switched off on the one that still has it - by the held session, which
    // is the only thing that still knows which that was - and put up on the new
    // one. Letting it simply carry on would drive the new Flipper's display
    // while leaving the old one lit with a picture nobody updates.
    final boundTo = _boundTo;
    if (boundTo != null && boundTo.isStale) {
      unawaited(
        _stop().then((_) {
          if (_users > 0) _ensureStarted();
        }),
      );
      return;
    }
    if (_users > 0 && !_active) _ensureStarted();
  }

  /// Queues the latest [frame], replacing any not-yet-sent one, and sends it as
  /// soon as the previous send finishes. Encoded at send time, so the live
  /// canvas buffer always streams its most recent pixels.
  void pushFrame(Uint8List frame) {
    _pending = frame;
    _flush();
  }

  void _flush() {
    if (_sending || _pending == null) return;
    if (!_active) return;
    // The frame goes to the Flipper whose display this is, not to whichever one
    // is active by the time it is encoded.
    // _active is only ever true between a start and a stop, so by then the
    // session is held; no binding means there is nothing to send to.
    final binding = _binding;
    if (binding == null || !binding.isAlive) return;
    // 8 fps cap: if the last send was too recent, wait out the remainder and
    // send the latest pending frame then.
    final waited = _sinceLastSend.isRunning
        ? _sinceLastSend.elapsedMilliseconds
        : _minIntervalMs;
    if (waited < _minIntervalMs) {
      _sendTimer ??= Timer(Duration(milliseconds: _minIntervalMs - waited), () {
        _sendTimer = null;
        _flush();
      });
      return;
    }
    final frame = _pending!;
    _pending = null;
    _sending = true;
    _sinceLastSend
      ..reset()
      ..start();
    binding
        .run(
          () => _client.sendRpc(
            Main(guiScreenFrame: ScreenFrame(data: BmCodec.encodeXBM(frame))),
            // Not foreground: a frame is written into one Flipper's display,
            // so it goes where the display is, not where the user is looking.
            priority: FlipperRequestPriority.unattended,
          ),
        )
        .then<void>(
          (_) {},
          onError: (Object error) {
            // A failed frame send (e.g. link dropped mid-write) is not fatal
            // for the session; the connection listener handles the teardown.
            LogService.info('[VirtualDisplay] frame send failed: $error');
          },
        )
        .whenComplete(() {
          _sending = false;
          if (_pending != null) _flush();
        });
  }

  /// Mirrors a selected project's preview on the device, looping [frames] at
  /// [delayMs]. Suspended while the editor holds exclusive control.
  void setPreview(List<Uint8List> frames, int delayMs) {
    _stopPreviewTimer();
    if (frames.isEmpty) {
      _previewFrames = null;
      return;
    }
    _previewFrames = frames;
    _previewDelayMs = delayMs.clamp(33, 2000);
    _previewCursor = 0;
    if (_liveHolders == 0) _startPreviewTimer();
  }

  void clearPreview() {
    _stopPreviewTimer();
    _previewFrames = null;
    _previewCursor = 0;
  }

  void _startPreviewTimer() {
    if (_suspended) return;
    final frames = _previewFrames;
    if (frames == null || frames.isEmpty) return;
    _previewCursor %= frames.length;
    pushFrame(frames[_previewCursor]);
    if (frames.length <= 1) return;
    _previewTimer = Timer.periodic(Duration(milliseconds: _previewDelayMs), (
      _,
    ) {
      final f = _previewFrames;
      if (f == null || f.isEmpty) return;
      _previewCursor = (_previewCursor + 1) % f.length;
      pushFrame(f[_previewCursor]);
    });
  }

  void _stopPreviewTimer() {
    _previewTimer?.cancel();
    _previewTimer = null;
  }
}
