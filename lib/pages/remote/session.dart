import 'dart:async';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import 'frame_decoder.dart';
import 'models/models.dart';

const Duration _kAnimDuration = Duration(milliseconds: 650);

class RemoteSession extends ChangeNotifier {
  RemoteSession() {
    _frameSub = _client.screenFrameStream().listen(_onFrame);
    _statusSub = _client.desktopStatusStream().listen(_applyStatus);
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    unawaited(_start());
  }

  final FlipperClient _client = FlipperOneClient().get();

  StreamSubscription<ScreenFrame>? _frameSub;
  StreamSubscription<Status>? _statusSub;
  StreamSubscription<FlipperConnectionState>? _connectionSub;

  Future<void> _inputChain = Future<void>.value();

  /// Called synchronously after pixel decode, before GPU image creation.
  /// Receives raw frame data independent of the graphics pipeline.
  void Function(RawFrameData)? onRawFrame;

  ui.Image? _frameImage;
  final _frameNotifier = ValueNotifier<ui.Image?>(null);

  // GPU-upload coalescing: the synchronous decode runs for every frame (GIF
  // recording needs the full rate), but only the newest decoded frame is
  // turned into a ui.Image. A single worker loop keeps publication strictly
  // ordered, so a slow upload can never clobber a newer frame with an older
  // one — the bug behind random frame drops/flicker.
  Uint8List? _pendingRgba;
  int _frameSeq = 0;
  int _publishedSeq = -1;
  bool _imageWorkerBusy = false;
  StreamOrientation _orientation = StreamOrientation.horizontal;
  bool _isLocked = true;
  bool _isDisconnected = false;
  bool _stopped = false;
  bool _disposed = false;

  final List<QueuedButton> _queue = [];
  final Map<RemoteButton, _HeldButton> _held = {};

  int? _lastBgColor;
  int? _lastFgColor;

  ValueListenable<ui.Image?> get frameListenable => _frameNotifier;
  StreamOrientation get orientation => _orientation;
  bool get isLocked => _isLocked;
  bool get isDisconnected => _isDisconnected;
  List<QueuedButton> get queue => _queue;
  int? get lastBgColor => _lastBgColor;
  int? get lastFgColor => _lastFgColor;

  /// Encodes the current frame as PNG bytes. Returns null if no frame received.
  Future<Uint8List?> capturePng() async {
    final img = _frameImage;
    if (img == null) return null;
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
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

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _client.guiStopScreenStream().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _client.desktopStatusUnsubscribe().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    for (final h in _held.values) {
      h.longTimer?.cancel();
    }
    _held.clear();
    _frameSub?.cancel();
    _statusSub?.cancel();
    _connectionSub?.cancel();
    _frameNotifier.dispose();
    _frameImage?.dispose();
    _frameImage = null;
    if (!_stopped) unawaited(stop());
    super.dispose();
  }

  void _applyStatus(Status status) {
    if (_disposed) return;
    _isLocked = status.locked;
    _safeNotify();
  }

  void _onFrame(ScreenFrame frame) {
    // Decode synchronously so GIF recording sees every frame before GPU work.
    final raw = decodeFrameSync(frame);
    if (_disposed) return;

    _lastBgColor = raw.bgColor;
    _lastFgColor = raw.fgColor;
    final orientationChanged = raw.orientation != _orientation;
    _orientation = raw.orientation;
    onRawFrame?.call(raw);
    // Only rebuild the page tree when orientation changes (rare); frame image
    // updates are handled by ValueListenableBuilder in the view layer.
    if (orientationChanged) _safeNotify();

    // Hand the latest pixels to the upload worker. Bursts that arrive while an
    // upload is in flight overwrite this, coalescing to the newest frame.
    _pendingRgba = raw.rgba;
    _frameSeq++;
    if (_imageWorkerBusy) return;
    _imageWorkerBusy = true;
    unawaited(_pumpFrameImages());
  }

  // Serially uploads pending frames so newer frames always win. Without the
  // single-worker ordering, out-of-order createImageFromRgba completions could
  // publish a stale image and dispose the live one.
  Future<void> _pumpFrameImages() async {
    try {
      while (!_disposed) {
        final rgba = _pendingRgba;
        if (rgba == null) return;
        final seq = _frameSeq;
        _pendingRgba = null;

        final image = await createImageFromRgba(rgba);
        if (_disposed || seq <= _publishedSeq) {
          image.dispose();
          continue;
        }
        _publishedSeq = seq;
        final prev = _frameImage;
        _frameImage = image;
        _frameNotifier.value = image;
        prev?.dispose();
      }
    } finally {
      _imageWorkerBusy = false;
    }
  }

  Future<void> press(RemoteButton button, {bool long = false}) {
    final item = _enqueue(_animAsset(button));
    final type = long ? InputType.LONG : InputType.SHORT;
    final key = _key(button);
    _inputChain = _inputChain.then((_) async {
      try {
        await _send(key, InputType.PRESS);
        await _send(key, type);
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
      _inputChain = _inputChain.then((_) async {
        try {
          await _send(key, InputType.LONG);
        } catch (_) {}
      });
    });
    _inputChain = _inputChain.then((_) async {
      try {
        await _send(key, InputType.PRESS);
      } catch (_) {}
    });
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
          await _send(key, InputType.SHORT);
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
