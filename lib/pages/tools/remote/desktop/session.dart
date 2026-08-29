import 'dart:async';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import '../../../../services/connection/device_info_watch.dart';
import 'frame_decoder.dart';
import 'models/models.dart';
import 'screenshot_encoder.dart';

const Duration _kAnimDuration = Duration(milliseconds: 650);
const Duration _kUnlockedFlashDuration = Duration(seconds: 1);
const Duration _kStopTimeout = Duration(seconds: 2);

class RemoteSession extends ChangeNotifier {
  RemoteSession({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _frameSub = _client.screenFrameStream().listen(_onFrame);
    _statusSub = _client.desktopStatusStream().listen(_applyStatus);
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    DeviceInfoWatchService.instance.freeze();
    unawaited(_start());
  }

  final FlipperClient _client;

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

  RawFrameData? _lastRaw;

  StreamOrientation _orientation = StreamOrientation.horizontal;
  bool _isLocked = true;
  bool _lockStatusKnown = false;
  bool _justUnlocked = false;
  Timer? _unlockedFlashTimer;
  bool _isDisconnected = false;
  bool _starting = false;
  bool _disposed = false;
  bool _stopped = false;

  final List<QueuedButton> _queue = [];
  final Map<RemoteButton, _HeldButton> _held = {};
  final Set<InputKey> _wireDown = {};

  int? _lastBgColor;
  int? _lastFgColor;

  ValueListenable<ui.Image?> get frameListenable => _frameNotifier;
  StreamOrientation get orientation => _orientation;
  bool get justUnlocked => _justUnlocked;
  bool get isDisconnected => _isDisconnected;
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

  /// Asks for the stream straight away — a stale "not connected" flag must not
  /// keep the page from trying, so the verdict comes from the call itself.
  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      await _client.guiStartScreenStream(
        priority: FlipperRequestPriority.rightNow,
      );
      await _client.desktopStatusSubscribe();
      final frames = await _client.desktopIsLocked();
      for (final f in frames) {
        if (f.hasDesktopStatus()) _applyStatus(f.desktopStatus);
      }
    } catch (_) {
      if (_disposed) return;
      if (!_isDisconnected) {
        _isDisconnected = true;
        _safeNotify();
      }
    } finally {
      _starting = false;
    }
  }

  void shutdown() {
    if (_disposed) return;
    _disposed = true;
    DeviceInfoWatchService.instance.unfreeze();
    for (final h in _held.values) {
      h.longTimer?.cancel();
    }
    _held.clear();
    _unlockedFlashTimer?.cancel();
    _frameSub?.cancel();
    _statusSub?.cancel();
    _connectionSub?.cancel();
    _pendingFrame = null;
    _pendingRgba = null;
    unawaited(_chain(_releaseWireDown).whenComplete(_stopRemote));
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

    if (!state.connected) {
      if (_isDisconnected) return;
      _isDisconnected = true;
      final prev = _frameImage;
      _frameImage = null;
      _frameNotifier.value = null;
      _safeNotify();
      prev?.dispose();
      return;
    }

    unawaited(_start());
  }

  void _applyStatus(Status status) {
    if (_disposed) return;
    final wasLocked = _isLocked;
    _isLocked = status.locked;
    if (_lockStatusKnown && wasLocked && !status.locked) _flashUnlocked();
    _lockStatusKnown = true;
    _safeNotify();
  }

  void _flashUnlocked() {
    _unlockedFlashTimer?.cancel();
    _justUnlocked = true;
    _unlockedFlashTimer = Timer(_kUnlockedFlashDuration, () {
      if (_disposed) return;
      _justUnlocked = false;
      _safeNotify();
    });
  }

  void _onFrame(ScreenFrame frame) {
    if (_disposed) return;
    if (_isDisconnected) {
      _isDisconnected = false;
      _safeNotify();
    }
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
    if (orientationChanged) _safeNotify();
    _lastRaw = raw;
    _scheduleUpload(raw.rgba);
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

  Future<void> press(RemoteButton button, {bool long = false}) {
    final item = _enqueue(_animAsset(button));
    final type = long ? InputType.LONG : InputType.SHORT;
    final key = _key(button);
    return _chain(() async {
      await Future.wait([
        _down(key),
        _typed(key, type),
        _up(key, onAnswer: () => _dequeue(item)),
      ]);
    });
  }

  Future<void> beginHold(RemoteButton button) {
    if (_held.containsKey(button)) return _inputChain;
    final item = _enqueue(_animAsset(button));
    final state = _HeldButton(item: item);
    _held[button] = state;
    final key = _key(button);
    state.longTimer = Timer(const Duration(milliseconds: 500), () {
      if (!identical(_held[button], state)) return;
      state.longFired = true;
      unawaited(_chain(() => _typed(key, InputType.LONG)));
    });
    return _chain(() => _down(key));
  }

  Future<void> endHold(RemoteButton button) {
    final state = _held.remove(button);
    if (state == null) return _inputChain;
    state.longTimer?.cancel();
    final key = _key(button);
    return _chain(() async {
      await Future.wait([
        if (!state.longFired) _typed(key, InputType.SHORT),
        _up(key, onAnswer: () => _dequeue(state.item)),
      ]);
    });
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
    } catch (_) {}
  }

  Future<void> _chain(Future<void> Function() action) {
    final next = _inputChain.then((_) async {
      try {
        await action();
      } catch (_) {}
    });
    _inputChain = next;
    return next;
  }

  Future<void> _sendInput(InputKey key, InputType type) => _client
      .guiSendInputAndForget(SendInputEventRequest(key: key, type: type))
      .catchError((_) {});

  Future<void> _down(InputKey key) {
    if (!_wireDown.add(key)) return Future<void>.value();
    return _sendInput(key, InputType.PRESS);
  }

  Future<void> _typed(InputKey key, InputType type) {
    if (!_wireDown.contains(key)) return Future<void>.value();
    return _sendInput(key, type);
  }

  Future<void> _up(InputKey key, {void Function()? onAnswer}) {
    if (!_wireDown.remove(key)) {
      onAnswer?.call();
      return Future<void>.value();
    }
    final sent = Completer<void>();
    unawaited(
      _client
          .guiSendInput(
            SendInputEventRequest(key: key, type: InputType.RELEASE),
            onSent: () {
              if (!sent.isCompleted) sent.complete();
            },
          )
          .catchError((_) => <Main>[])
          .whenComplete(() {
            if (!sent.isCompleted) sent.complete();
            onAnswer?.call();
          }),
    );
    return sent.future;
  }

  Future<void> _releaseWireDown() async {
    final keys = _wireDown.toList();
    _wireDown.clear();
    if (keys.isEmpty || !_client.isConnected) return;
    await Future.wait([
      for (final key in keys) _sendInput(key, InputType.RELEASE),
    ]);
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
