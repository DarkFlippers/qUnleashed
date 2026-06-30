import 'dart:async';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import 'frame_decoder.dart';
import 'grayscale_filter.dart';
import 'models/models.dart';
import 'screenshot_encoder.dart';

const Duration _kAnimDuration = Duration(milliseconds: 650);
const Duration _kStopTimeout = Duration(seconds: 2);

class RemoteSession extends ChangeNotifier {
  RemoteSession() {
    _frameSub = _client.screenFrameStream().listen(_onFrame);
    _statusSub = _client.desktopStatusStream().listen(_applyStatus);
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    _client.freezeWatch();
    unawaited(_start());
  }

  final FlipperClient _client = FlipperOneClient().get();

  StreamSubscription<ScreenFrame>? _frameSub;
  StreamSubscription<Status>? _statusSub;
  StreamSubscription<FlipperConnectionState>? _connectionSub;

  Future<void> _inputChain = Future<void>.value();

  void Function(RawFrameData)? onRawFrame;

  ui.Image? _frameImage;
  final _frameNotifier = ValueNotifier<ui.Image?>(null);
  ScreenFrame? _pendingFrame;
  bool _decodeBusy = false;
  Uint8List? _pendingRgba;
  bool _uploadBusy = false;
  bool _recording = false;


  final GrayscaleFilter _grayscale = GrayscaleFilter();
  bool _grayscaleEnabled = false;
  RawFrameData? _lastRaw;

  StreamOrientation _orientation = StreamOrientation.horizontal;
  bool _isLocked = true;
  bool _isDisconnected = false;
  bool _disposed = false;
  bool _stopped = false;

  final List<QueuedButton> _queue = [];
  final Map<RemoteButton, _HeldButton> _held = {};

  int? _lastBgColor;
  int? _lastFgColor;

  ValueListenable<ui.Image?> get frameListenable => _frameNotifier;
  StreamOrientation get orientation => _orientation;
  bool get isLocked => _isLocked;
  bool get isDisconnected => _isDisconnected;
  bool get grayscaleEnabled => _grayscaleEnabled;
  List<QueuedButton> get queue => _queue;
  int? get lastBgColor => _lastBgColor;
  int? get lastFgColor => _lastFgColor;

  set recording(bool value) {
    if (_recording == value) return;
    _recording = value;
    if (!value && _pendingFrame != null) _ensureDecodeWorker();
  }

  Uint8List? capturePng() {
    final raw = _lastRaw;
    if (raw == null) return null;
    return encodeScreenshotPng(raw);
  }


  Future<void> _start() async {
    if (!_client.isConnected) {
      _isDisconnected = true;
      _safeNotify();
      return;
    }
    await _client.guiStartScreenStream(
      priority: FlipperRequestPriority.rightNow,
    );
    await _client.desktopStatusSubscribe();
    final frames = await _client.desktopIsLocked();
    for (final f in frames) {
      if (f.hasDesktopStatus()) _applyStatus(f.desktopStatus);
    }
  }

  void shutdown() {
    if (_disposed) return;
    _disposed = true;
    _client.unfreezeWatch();
    for (final h in _held.values) {
      h.longTimer?.cancel();
    }
    _held.clear();
    _frameSub?.cancel();
    _statusSub?.cancel();
    _connectionSub?.cancel();
    _pendingFrame = null;
    _pendingRgba = null;
    unawaited(_stopRemote());
  }

  Future<void> _stopRemote() async {
    if (_stopped) return;
    _stopped = true;
    if (!_client.isConnected) return;
    await Future.wait([
      _client
          .guiStopScreenStream(priority: FlipperRequestPriority.rightNow)
          .timeout(_kStopTimeout)
          .catchError((_) => <Main>[]),
      _client
          .desktopStatusUnsubscribe(priority: FlipperRequestPriority.rightNow)
          .timeout(_kStopTimeout)
          .catchError((_) => <Main>[]),
    ]);
  }

  @override
  void dispose() {
    if (!_disposed) shutdown();
    _frameNotifier.dispose();
    _frameImage?.dispose();
    _frameImage = null;
    super.dispose();
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (_disposed) return;
    if (!state.connected && !_isDisconnected) {
      _isDisconnected = true;
      final prev = _frameImage;
      _frameImage = null;
      _frameNotifier.value = null;
      _safeNotify();
      prev?.dispose();
    }
  }

  void _applyStatus(Status status) {
    if (_disposed) return;
    _isLocked = status.locked;
    _safeNotify();
  }

  void _onFrame(ScreenFrame frame) {
    if (_disposed) return;
    if (_recording) {

      _ingest(decodeFrameSync(frame));
      return;
    }
    _pendingFrame = frame;
    _ensureDecodeWorker();
  }

  void _ensureDecodeWorker() {
    if (_decodeBusy || _disposed) return;
    _decodeBusy = true;
    unawaited(_pumpDecode());
  }

  Future<void> _pumpDecode() async {
    try {
      while (!_disposed && !_recording) {
        final frame = _pendingFrame;
        if (frame == null) return;
        _pendingFrame = null;
        _ingest(decodeFrameSync(frame));
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _decodeBusy = false;
    }
  }

  void _ingest(RawFrameData raw) {
    if (_disposed) return;
    _lastBgColor = raw.bgColor;
    _lastFgColor = raw.fgColor;
    final orientationChanged = raw.orientation != _orientation;
    _orientation = raw.orientation;
    onRawFrame?.call(raw);
    if (orientationChanged) {
      _grayscale.reset();
      _safeNotify();
    }
    _lastRaw = raw;
    if (_grayscaleEnabled) _grayscale.push(raw.pixelIndices);
    _scheduleUpload(_render(raw));
  }

  Uint8List _render(RawFrameData raw) {
    if (!_grayscaleEnabled) return raw.rgba;
    return _grayscale.render(raw.pixelIndices.length, raw.bgColor, raw.fgColor);
  }

  void _scheduleUpload(Uint8List rgba) {
    _pendingRgba = rgba;
    if (_uploadBusy || _disposed) return;
    _uploadBusy = true;
    unawaited(_pumpUpload());
  }

 Future<void> _pumpUpload() async {
    try {
      while (!_disposed) {
        final rgba = _pendingRgba;
        if (rgba == null) return;
        _pendingRgba = null;
        final image = await createImageFromRgba(rgba);
        if (_disposed) {
          image.dispose();
          return;
        }
        final prev = _frameImage;
        _frameImage = image;
        _frameNotifier.value = image;
        prev?.dispose();
      }
    } finally {
      _uploadBusy = false;
    }
  }

  void setGrayscaleEnabled(bool enabled) {
    if (_disposed || _grayscaleEnabled == enabled) return;
    _grayscaleEnabled = enabled;
    _safeNotify();
    final raw = _lastRaw;
    if (raw == null) return;
    if (enabled) {
      _grayscale
        ..reset()
        ..push(raw.pixelIndices);
    }
    _scheduleUpload(_render(raw));
  }
  Future<void> press(RemoteButton button, {bool long = false}) {
    final item = _enqueue(_animAsset(button));
    final type = long ? InputType.LONG : InputType.SHORT;
    final key = _key(button);
    _inputChain = _inputChain.then((_) async {
      try {
        _forget(key, InputType.PRESS);
        _forget(key, type);
        await _send(key, InputType.RELEASE);
      } catch (_) {
      } finally {
        _dequeue(item);
      }
    });
    return _inputChain;
  }

  Future<void> beginHold(RemoteButton button) {
    if (_held.containsKey(button)) return _inputChain;
    final item = _enqueue(_animAsset(button));
    final state = _HeldButton(item: item);
    _held[button] = state;
    final key = _key(button);
    state.longTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_held.containsKey(button) || _held[button] != state) return;
      state.longFired = true;
      _forget(key, InputType.LONG);
    });
    _forget(key, InputType.PRESS);
    return _inputChain;
  }

  Future<void> endHold(RemoteButton button) {
    final state = _held.remove(button);
    if (state == null) return _inputChain;
    state.longTimer?.cancel();
    final key = _key(button);
    _inputChain = _inputChain.then((_) async {
      try {
        if (!state.longFired) {
          _forget(key, InputType.SHORT);
        }
        await _send(key, InputType.RELEASE);
      } catch (_) {
      } finally {
        _dequeue(state.item);
      }
    });
    return _inputChain;
  }

  Future<void> unlock() async {
    final item = _enqueue(_kUnlockAnim);
    Timer(_kAnimDuration, () => _dequeue(item));
    try {
      await _client.desktopUnlock(UnlockRequest());
      final frames = await _client.desktopIsLocked();
      for (final f in frames) {
        if (f.hasDesktopStatus()) _applyStatus(f.desktopStatus);
      }
    } catch (_) {
      _isLocked = false;
      _safeNotify();
    }
  }

  Future<void> _send(InputKey key, InputType type) =>
      _client.guiSendInput(SendInputEventRequest(key: key, type: type));

  void _forget(InputKey key, InputType type) {
    unawaited(
      _client
          .guiSendInputAndForget(SendInputEventRequest(key: key, type: type))
          .catchError((_) {}),
    );
  }

  QueuedButton _enqueue(String asset) {
    final item = QueuedButton(asset: asset);
    _queue.add(item);
    _safeNotify();
    return item;
  }

  void _dequeue(QueuedButton item) {
    if (_disposed) return;
    _queue.removeWhere((e) => e.id == item.id);
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }
}

class _HeldButton {
  _HeldButton({required this.item});
  final QueuedButton item;
  Timer? longTimer;
  bool longFired = false;
}

InputKey _key(RemoteButton b) => switch (b) {
  RemoteButton.up => InputKey.UP,
  RemoteButton.down => InputKey.DOWN,
  RemoteButton.left => InputKey.LEFT,
  RemoteButton.right => InputKey.RIGHT,
  RemoteButton.ok => InputKey.OK,
  RemoteButton.back => InputKey.BACK,
};

const _animBase = 'assets/ic/control/hint';
const _kUnlockAnim = '$_animBase/unlock.svg';

String _animAsset(RemoteButton b) => switch (b) {
  RemoteButton.up => '$_animBase/up.svg',
  RemoteButton.down => '$_animBase/down.svg',
  RemoteButton.left => '$_animBase/left.svg',
  RemoteButton.right => '$_animBase/right.svg',
  RemoteButton.ok => '$_animBase/ok.svg',
  RemoteButton.back => '$_animBase/back.svg',
};
