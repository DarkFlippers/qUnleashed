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
    unawaited(_start());
  }

  final FlipperClient _client = FlipperOneClient().get();

  StreamSubscription<ScreenFrame>? _frameSub;
  StreamSubscription<Status>? _statusSub;

  Future<void> _inputChain = Future<void>.value();

  /// Called synchronously after pixel decode, before GPU image creation.
  /// Receives raw frame data independent of the graphics pipeline.
  void Function(RawFrameData)? onRawFrame;

  ui.Image? _frameImage;
  StreamOrientation _orientation = StreamOrientation.horizontal;
  bool _isLocked = true;
  bool _stopped = false;
  bool _disposed = false;
  Object? _startError;

  final List<QueuedButton> _queue = [];
  final Map<RemoteButton, _HeldButton> _held = {};

  int? _lastBgColor;
  int? _lastFgColor;

  ui.Image? get frameImage => _frameImage;
  StreamOrientation get orientation => _orientation;
  bool get isLocked => _isLocked;
  Object? get startError => _startError;
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

  Future<void> _start() async {
    await _tryRpc(
      'guiStartScreenStream',
      () => _client.guiStartScreenStream(),
    );
    await _tryRpc(
      'desktopStatusSubscribe',
      () => _client.desktopStatusSubscribe(),
    );
    final frames = await _tryRpc(
      'desktopIsLocked',
      () => _client.desktopIsLocked(),
    );
    if (frames != null) {
      for (final f in frames) {
        if (f.hasDesktopStatus()) _applyStatus(f.desktopStatus);
      }
    }
  }

  Future<T?> _tryRpc<T>(String tag, Future<T> Function() body) async {
    try {
      return await body();
    } on FlipperRpcException catch (e) {
      LogService.log('[RemoteSession] $tag ignored RPC error: $e');
      return null;
    } catch (e) {
      LogService.log('[RemoteSession] $tag failed: $e');
      _startError = e;
      _safeNotify();
      return null;
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _client.guiStopScreenStream();
      await _client.desktopStatusUnsubscribe();
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

  Future<void> _onFrame(ScreenFrame frame) async {
    // Phase 1: synchronous pixel decode — no GPU, no async.
    // GIF recorder receives raw frame data before any GPU work begins.
    final raw = decodeFrameSync(frame);
    if (_disposed) return;

    _lastBgColor = raw.bgColor;
    _lastFgColor = raw.fgColor;
    _orientation = raw.orientation;
    onRawFrame?.call(raw);

    // Phase 2: async GPU image creation for UI display.
    final image = await createImageFromRgba(raw.rgba);
    if (_disposed) {
      image.dispose();
      return;
    }
    final prev = _frameImage;
    _frameImage = image;
    _safeNotify();
    prev?.dispose();
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

const _animBase = 'assets/flipper_svg/screenstreaming';
const _kUnlockAnim = '$_animBase/ic_anim_unlock_light.svg';

String _animAsset(RemoteButton b) => switch (b) {
      RemoteButton.up => '$_animBase/ic_anim_up_button_light.svg',
      RemoteButton.down => '$_animBase/ic_anim_down_button_light.svg',
      RemoteButton.left => '$_animBase/ic_anim_left_button_light.svg',
      RemoteButton.right => '$_animBase/ic_anim_right_button_light.svg',
      RemoteButton.ok => '$_animBase/ic_anim_ok_button_light.svg',
      RemoteButton.back => '$_animBase/ic_anim_back_button_light.svg',
    };
