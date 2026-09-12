import 'dart:async';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import '../../../../services/connection/device_info_watch.dart';
import '../../../../services/logging.dart';
import 'frame_decoder.dart';
import 'models/models.dart';
import 'screenshot_encoder.dart';

const Duration _kAnimDuration = Duration(milliseconds: 650);
const Duration _kUnlockedFlashDuration = Duration(seconds: 1);
const Duration _kStopTimeout = Duration(seconds: 2);

class RemoteSession extends ChangeNotifier {
  RemoteSession({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _inputAvailable = _client.isConnected;
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
  bool _inputAvailable = false;
  bool _starting = false;
  bool _visualsEnabled = true;

  /// A start asked for while one was already running.
  ///
  /// Not a duplicate of it: the running one was issued against a session that
  /// has since ended, so whether it succeeds says nothing about the link that
  /// exists now. Cleared before each attempt, so only a request that arrives
  /// during one asks for another after it — five connection events during a
  /// single open cost one more open, not five.
  bool _restartWanted = false;
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
  bool get inputAvailable => _inputAvailable;
  List<QueuedButton> get queue => _queue;
  int? get lastBgColor => _lastBgColor;
  int? get lastFgColor => _lastFgColor;

  set recording(bool value) {
    if (_recording == value) return;
    _recording = value;
    if (!value && _pendingFrame != null && _visualsEnabled) {
      _ensureDecodeWorker();
    }
  }

  Uint8List? capturePng() {
    final raw = _lastRaw;
    if (raw == null) return null;
    return encodeScreenshotPng(raw);
  }

  /// Keeps the control RPC session alive but pauses the expensive framebuffer
  /// stream while the page is not visible. Wrist Remote can still send inputs.
  Future<void> pauseVisuals() async {
    if (_disposed || !_visualsEnabled) return;
    _visualsEnabled = false;
    _pendingFrame = null;
    _pendingRgba = null;
    if (!_client.isConnected) return;
    await _stopVisuals();
  }

  /// Re-opens the framebuffer/status streams after [pauseVisuals].
  Future<void> resumeVisuals() async {
    if (_disposed || _visualsEnabled) return;
    _visualsEnabled = true;
    if (_client.isConnected) await _start();
  }

  /// Asks for the stream straight away — a stale "not connected" flag must not
  /// keep the page from trying, so the verdict comes from the call itself.
  ///
  /// Exactly one open runs at a time, nominally three RPCs — fewer if the page
  /// goes away or visuals are paused mid-flight. A request arriving during one
  /// is held in [_restartWanted] and run afterwards rather than dropped:
  /// dropping it left a reconnect with nothing behind it, and since a frame is
  /// the only thing that clears [_isDisconnected], the page stayed blank.
  ///
  /// That opens never overlap is what makes a single flag enough. Were they
  /// ever made concurrent — to hide the latency of three sequential round
  /// trips, say — a stale open could finish after a newer one and overwrite
  /// what it had already applied, and this would need to know which link each
  /// attempt belonged to rather than merely that one is outstanding.
  Future<void> _start() async {
    if (_disposed || !_visualsEnabled) return;
    if (_starting) {
      _restartWanted = true;
      return;
    }
    _starting = true;
    try {
      do {
        // Cleared before the attempt, so only a request that arrives while
        // this one runs asks for another after it.
        _restartWanted = false;
        if (_disposed || !_visualsEnabled) return;
        try {
          // Checked for teardown or a visual pause between each. All three
          // requests stay at rightNow; their defaults are foreground.
          //
          // For the subscribe that is correctness, not tidiness: the queue
          // sorts by priority before arrival, so left at foreground it would
          // be overtaken by the rightNow unsubscribe shutdown/pause sends. The
          // device would be told to start pushing desktop status after being
          // told to stop, and _stopRemote latches itself off at teardown, so
          // nothing would ever unsubscribe it again. The same reasoning
          // applies to the stream, which guiStopScreenStream undoes at
          // rightNow. Equal-priority requests stay FIFO.
          //
          // desktopIsLocked has nothing that undoes it, so its priority only
          // buys latency on a path the user is waiting out — but the three
          // belong to one operation and are easier to reason about together.
          await _client.guiStartScreenStream(
            priority: FlipperRequestPriority.rightNow,
          );
          if (_disposed) return;
          if (!_visualsEnabled) {
            await _stopVisuals();
            return;
          }
          await _client.desktopStatusSubscribe(
            priority: FlipperRequestPriority.rightNow,
          );
          if (_disposed) return;
          if (!_visualsEnabled) {
            await _stopVisuals();
            return;
          }
          final frames = await _client.desktopIsLocked(
            priority: FlipperRequestPriority.rightNow,
          );
          if (_disposed) return;
          if (!_visualsEnabled) {
            await _stopVisuals();
            return;
          }
          for (final f in frames) {
            if (f.hasDesktopStatus()) _applyStatus(f.desktopStatus);
          }
        } catch (_) {
          if (_disposed) return;
          if (!_isDisconnected) {
            _isDisconnected = true;
            _safeNotify();
          }
        }
        // Inside the try, so a failed attempt still honours a reconnect that
        // landed during it - that being the case where retrying matters most.
      } while (_restartWanted && !_disposed && _visualsEnabled);
    } finally {
      _starting = false;
    }
  }

  void shutdown() {
    if (_disposed) return;
    _disposed = true;
    _visualsEnabled = false;
    _inputAvailable = false;
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

  Future<void> _stopVisuals() async {
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

  Future<void> _stopRemote() async {
    if (_stopped) return;
    _stopped = true;
    await _stopVisuals();
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

    final inputChanged = _inputAvailable != state.connected;
    _inputAvailable = state.connected;

    if (!state.connected) {
      if (_isDisconnected) {
        if (inputChanged) _safeNotify();
        return;
      }
      _isDisconnected = true;
      final prev = _frameImage;
      _frameImage = null;
      _frameNotifier.value = null;
      _safeNotify();
      prev?.dispose();
      return;
    }

    // Input availability follows the transport; visual connectivity deliberately
    // does not. A reconnect while paused can accept wrist inputs, but the LED
    // stays disconnected until a real framebuffer arrives after resume.
    if (inputChanged) _safeNotify();
    if (!_visualsEnabled) return;

    unawaited(_start());
  }

  void _applyStatus(Status status) {
    if (_disposed || !_visualsEnabled) return;
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
    if (_disposed || !_visualsEnabled) return;
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
    if (_decodeBusy || _disposed || !_visualsEnabled) return;
    _decodeBusy = true;
    unawaited(_pumpDecode());
  }

  Future<void> _pumpDecode() async {
    try {
      while (!_disposed && !_recording && _visualsEnabled) {
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
    if (_disposed || !_visualsEnabled) return;
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
    if (!_visualsEnabled) return;
    _pendingRgba = rgba;
    if (_uploadBusy || _disposed) return;
    _uploadBusy = true;
    unawaited(_pumpUpload());
  }

  Future<void> _pumpUpload() async {
    try {
      while (!_disposed && _visualsEnabled) {
        final rgba = _pendingRgba;
        if (rgba == null) return;
        _pendingRgba = null;
        final image = await createImageFromRgba(rgba);
        if (_disposed || !_visualsEnabled) {
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

  Future<void> _sendInput(InputKey key, InputType type) async {
    LogService.debug('[RemoteInput] wire ${type.name} ${key.name}');
    try {
      await _client.guiSendInputAndForget(
        SendInputEventRequest(key: key, type: type),
      );
      LogService.debug('[RemoteInput] sent ${type.name} ${key.name}');
    } catch (e) {
      LogService.warn('[RemoteInput] failed ${type.name} ${key.name}: $e');
    }
  }

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
    LogService.debug('[RemoteInput] wire RELEASE ${key.name}');
    final sent = Completer<void>();
    unawaited(
      _client
          .guiSendInput(
            SendInputEventRequest(key: key, type: InputType.RELEASE),
            onSent: () {
              LogService.debug('[RemoteInput] sent RELEASE ${key.name}');
              if (!sent.isCompleted) sent.complete();
            },
          )
          .catchError((e) {
            LogService.warn('[RemoteInput] failed RELEASE ${key.name}: $e');
            return <Main>[];
          })
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
