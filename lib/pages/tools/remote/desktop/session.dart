import 'dart:async';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/foundation.dart';

import '../../../../services/connection/device_info_watch.dart';
import '../../../../services/guarded.dart';
import '../../../../services/logging.dart';
import '../../../../services/rpc/desktop_lock.dart';
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

  /// The Flipper whose screen this is, held from the moment the stream starts.
  ///
  /// Starting a screen stream and subscribing to desktop status switch
  /// something on inside one Flipper, and the `rightNow` commands that switch
  /// them off again have to reach that same one. Looking the session up per
  /// call meant a device switch left the first Flipper streaming its screen to
  /// nobody while the stop went to the second.
  FlipperSessionBinding? _binding;

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

  /// Whether [button] is already being held down.
  ///
  /// [beginHold] keeps one [_HeldButton] per key and no-ops on a second call,
  /// so whoever schedules the matching [endHold] needs to know this before
  /// starting a hold that would release on someone else's timer.
  bool isHolding(RemoteButton button) => _held.containsKey(button);
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
    // Held here rather than per request, so the start, the status subscribe and
    // the stop that undoes them all land on one Flipper.
    final binding = _binding ??= _client.bindCurrentSession();
    try {
      await binding.run(_startLoop);
    } finally {
      _starting = false;
    }
  }

  Future<void> _startLoop() async {
    do {
      // Cleared before the attempt, so only a request that arrives while
      // this one runs asks for another after it.
      _restartWanted = false;
      if (_disposed || !_visualsEnabled) return;
      try {
        // Checked for teardown or a visual pause between each, so a page
        // that goes away part way through stops the rest going out.
        //
        // Both library requests stay at rightNow; their defaults are
        // foreground.
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
        // desktopIsLocked has nothing that undoes it, so unlike the
        // subscribe its rightNow is latency rather than correctness — and
        // little of that, since _frameSub is live from the constructor and
        // the screen is not waiting on it.
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
        // Caught apart from the two above. The poll runs last, so by here
        // the link has answered twice — a status rejection from it says
        // something about the command, not the connection, and flagging the
        // whole session disconnected for it is the mistake #94 was about,
        // one status further along.
        bool? locked;
        try {
          locked = await _client.desktopIsLockedNow();
        } on FlipperRpcException catch (e) {
          LogService.warn('[Remote] lock state unavailable: $e');
        }
        if (_disposed) return;
        if (!_visualsEnabled) {
          await _stopVisuals();
          return;
        }
        if (locked != null) _applyLocked(locked, flash: false);
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
    // guarded around the whole thing, not just the chain: _chain cannot
    // reject, but a whenComplete callback that throws rejects the future it
    // returns, and this one is dropped.
    unawaited(
      guarded(
        '[Remote] shutdown',
        () => _chain(
          'release on shutdown',
          _releaseWireDown,
        ).whenComplete(_stopRemote),
      ),
    );
  }

  Future<void> _stopVisuals() async {
    final binding = _binding;
    _binding = null;
    if (binding == null ? !_client.isConnected : !binding.isAlive) return;
    if (binding != null) return binding.run(_sendStopVisuals);
    return _sendStopVisuals();
  }

  Future<void> _sendStopVisuals() async {
    // Future.sync for the same reason as _up: both of these resolve the
    // session synchronously, so one already gone throws rather than rejecting
    // - past a catchError attached to the result. Teardown is precisely when
    // the session is most likely to be gone, and that throw escaped dispose()
    // into the zone.
    await Future.wait([
      Future.sync(
        () => _client
            .guiStopScreenStream(priority: FlipperRequestPriority.rightNow)
            .timeout(_kStopTimeout),
      ).catchError((_) => <Main>[]),
      Future.sync(
        () => _client
            .desktopStatusUnsubscribe(priority: FlipperRequestPriority.rightNow)
            .timeout(_kStopTimeout),
      ).catchError((_) => <Main>[]),
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

  void _applyStatus(Status status) => _applyLocked(status.locked);

  /// [flash] is false for the baseline an open polls for.
  ///
  /// That answer is a snapshot the device took before the subscribe landed, so
  /// it can be older than a push already applied — and after a pause it is the
  /// first thing seen since, so an unlock the user did on the device by hand
  /// would be announced here as though it had just happened. Seeding the
  /// baseline is its job; reporting a transition is the stream's.
  void _applyLocked(bool locked, {bool flash = true}) {
    if (_disposed || !_visualsEnabled) return;
    final wasLocked = _isLocked;
    _isLocked = locked;
    if (flash && _lockStatusKnown && wasLocked && !locked) _flashUnlocked();
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
    return _chain('press ${button.name}', () async {
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
      unawaited(
        _chain('long press ${button.name}', () => _typed(key, InputType.LONG)),
      );
    });
    return _chain('hold ${button.name}', () => _down(key));
  }

  Future<void> endHold(RemoteButton button) {
    final state = _held.remove(button);
    if (state == null) return _inputChain;
    state.longTimer?.cancel();
    final key = _key(button);
    return _chain('end hold ${button.name}', () async {
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
      // Flashing here, unlike the open's baseline: this transition is one the
      // user just asked for, and confirming it is the point.
      _applyLocked(await _client.desktopIsLockedNow());
    } catch (e) {
      // Was a bare catch, back when the ordinary unlocked answer arrived here
      // as a rejection. Now only real failures reach it — a refused unlock
      // looked exactly like a successful one, with no flash and no trace.
      LogService.warn('[Remote] unlock failed: $e');
    }
  }

  /// Queues [action] behind whatever input is already in flight.
  ///
  /// [what] names the button. Most of what fails here arrives without a stack -
  /// flipperlib rejects through a bare completeError - so an entry reading only
  /// "queued" could not be attributed to any of the five callers.
  ///
  /// _sendInput catches and warns for itself, so an ordinary refused PRESS
  /// never reaches guarded. _up is the one that could: see the Future.sync
  /// there. With that in place what arrives here is genuinely unexpected, which
  /// is what makes error the right level for it.
  ///
  /// The predecessor is awaited inside guarded, so _inputChain cannot reject
  /// and one failed action cannot strand the input queued behind it.
  Future<void> _chain(String what, Future<void> Function() action) {
    final previous = _inputChain;
    // The key goes to the Flipper whose screen is on show, which is the one
    // this session holds - not whichever is active by the time the queue in
    // front of it drains.
    final binding = _binding;
    final next = guarded('[RemoteInput] $what', () async {
      await previous;
      await (binding == null ? action() : binding.run(action));
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
    // Future.sync, because guiSendInput is not async: it resolves the session
    // synchronously, so one already gone throws here rather than rejecting -
    // past the catchError below, and past the whenComplete that completes
    // `sent` and calls onAnswer. The button's queued animation would then never
    // be dequeued, and the release would be reported as unexpected by _chain
    // rather than as the ordinary dropped input it is.
    unawaited(
      Future.sync(
            () => _client.guiSendInput(
              SendInputEventRequest(key: key, type: InputType.RELEASE),
              onSent: () {
                LogService.debug('[RemoteInput] sent RELEASE ${key.name}');
                if (!sent.isCompleted) sent.complete();
              },
            ),
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

String _animAsset(RemoteButton b) => b.hintAsset;
