import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime;

import 'codec.dart';

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
  int _users = 0;
  int _liveHolders = 0;
  bool _active = false;
  bool _starting = false;

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
    if (_users == 1) _ensureStarted();
  }

  void leave() {
    if (_users > 0) _users--;
    if (_users == 0) _stop();
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

  Future<void> _ensureStarted() async {
    if (_active || _starting || !_client.isConnected) return;
    _starting = true;
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
    } catch (_) {
    } finally {
      _starting = false;
      if (_active) {
        if (_previewFrames != null && _liveHolders == 0 && _previewTimer == null) {
          _startPreviewTimer();
        }
        _flush();
      }
    }
  }

  Future<void> _stop() async {
    _active = false;
    _stopPreviewTimer();
    _previewFrames = null;
    _pending = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    _sinceLastSend
      ..stop()
      ..reset();
    if (!_client.isConnected) return;
    await _client
        .guiStopVirtualDisplay(priority: FlipperRequestPriority.rightNow)
        .timeout(const Duration(seconds: 2))
        .catchError((_) => <Main>[]);
  }

  void _onConnectionChange(FlipperConnectionState state) {
    if (!state.connected) {
      _active = false;
      _starting = false;
    } else if (_users > 0 && !_active) {
      _ensureStarted();
    }
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
    if (!_active || !_client.isConnected) return; // no device → skip
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
    _client
        .sendRpc(
          Main(guiScreenFrame: ScreenFrame(data: PaintCodec.encodeXBM(frame))),
          priority: FlipperRequestPriority.foreground,
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
    final frames = _previewFrames;
    if (frames == null || frames.isEmpty) return;
    _previewCursor %= frames.length;
    pushFrame(frames[_previewCursor]);
    if (frames.length <= 1) return;
    _previewTimer = Timer.periodic(Duration(milliseconds: _previewDelayMs), (_) {
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
