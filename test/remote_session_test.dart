import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/desktop/models/models.dart';
import 'package:qunleashed/pages/tools/remote/desktop/session.dart';

/// One request as it was handed to the client, with what the session's queue
/// sorts on.
class _Sent {
  _Sent(this.request, this.priority, this.seq);
  final Main request;
  final FlipperRequestPriority priority;
  final int seq;
}

class _FakeClient implements FlipperClient {
  final broadcast = StreamController<Main>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();
  final List<_Sent> sent = [];

  List<Main> get requests => [for (final s in sent) s.request];

  /// The order these would reach the device. The real queue sorts by priority
  /// before arrival (`QueuedRequest.compareTo`), so a later `rightNow` request
  /// overtakes an earlier one at any lower priority. Mirrored here rather than
  /// exercised through the real queue, which this fake stands in for - enough
  /// to pin the priorities the session chooses, which is what goes wrong.
  List<Main> get wireOrder {
    final ordered = [...sent]
      ..sort((a, b) {
        final byPriority = a.priority.index.compareTo(b.priority.index);
        return byPriority != 0 ? byPriority : a.seq.compareTo(b.seq);
      });
    return [for (final s in ordered) s.request];
  }

  bool connected = false;
  bool failCalls = false;

  /// Throws before returning a future, the way the real client does.
  ///
  /// FlipperClient.callRpcFrames is not async: it resolves the session first,
  /// and one already gone throws there rather than rejecting. A fake that can
  /// only reject cannot express what a Flipper dropping mid-hold produces, so
  /// nothing here could see a handler attached to the result being skipped.
  bool throwsSynchronously = false;

  /// Gate for the first call, so a test can hold the initial open in flight
  /// and deliver a connection event while it is still between awaits. Without
  /// this every call resolves on a microtask and the race cannot happen.
  Completer<void>? gate;

  void openGate() {
    gate?.complete();
    gate = null;
  }

  int get startStreamCalls =>
      requests.where((r) => r.hasGuiStartScreenStreamRequest()).length;

  /// Everything an open issues, which is what must stop once the page is gone.
  int get openCalls => requests
      .where(
        (r) =>
            r.hasGuiStartScreenStreamRequest() ||
            r.hasDesktopStatusSubscribeRequest() ||
            r.hasDesktopIsLockedRequest(),
      )
      .length;

  /// The command_status a given request comes back with, when the answer is
  /// carried there rather than in a content frame. IsLockedRequest does that:
  /// OK for locked, ERROR for unlocked. The old fake could only fail every
  /// call at once, and with a StateError, so neither case was reachable.
  CommandStatus? Function(Main request)? statusFor;

  /// Frames a request answers with. Empty by default, which is what the
  /// firmware read for #94 sends for IsLockedRequest — a variant that answered
  /// properly is the case the frames branch exists for.
  List<Main> Function(Main request)? framesFor;

  @override
  bool get isConnected => connected;

  @override
  Stream<Main> get broadcastStream => broadcast.stream;

  @override
  Stream<Main> get notificationStream => broadcast.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => connection.stream;

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) {
    // Not async, so this throw leaves the call rather than rejecting it.
    if (throwsSynchronously) throw StateError('No active transport');
    return _callRpcFrames(
      request,
      priority: priority,
      onFrame: onFrame,
      onSent: onSent,
    );
  }

  Future<List<Main>> _callRpcFrames(
    Main request, {
    required FlipperRequestPriority priority,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
  }) async {
    sent.add(_Sent(request, priority, sent.length));
    final held = gate;
    if (held != null) await held.future;
    if (failCalls) throw StateError('no active session');
    final status = statusFor?.call(request);
    if (status != null && status != CommandStatus.OK) {
      // Through the library's own mapping, not a hand-rolled General for
      // everything: the real client raises FlipperRpcNotImplementedException
      // for ERROR_NOT_IMPLEMENTED, and a fake that cannot express a subclass
      // makes every type-matching path untestable while looking covered.
      throw exceptionFromResponse(Main()..commandStatus = status)!;
    }
    return framesFor?.call(request) ?? const <Main>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FlipperConnectionState _link({required bool connected}) =>
    FlipperConnectionState(
      mode: connected ? FlipperMode.rpc : FlipperMode.disconnected,
      device: null,
      connected: connected,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening the page asks for the stream at once', () async {
    final client = _FakeClient()..connected = true;
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(client.startStreamCalls, 1);
  });

  test('a stale disconnected flag does not hold the request back', () async {
    final client = _FakeClient()..connected = false;
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(
      client.startStreamCalls,
      1,
      reason: 'the call itself gives the verdict, not the cached flag',
    );
  });

  test('a failed open marks the page disconnected without retrying', () async {
    final client = _FakeClient()..failCalls = true;
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(session.isDisconnected, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(client.startStreamCalls, 1, reason: 'nothing automatic behind it');
  });

  test(
    'a reconnect racing the initial open still restarts the stream',
    () async {
      final client = _FakeClient()
        ..connected = true
        ..gate = Completer<void>();
      final session = RemoteSession(client: client);
      addTearDown(session.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(
        client.startStreamCalls,
        1,
        reason: 'the initial open is in flight',
      );

      // The link drops and comes back while that open is still between awaits -
      // which is exactly when a reconnect arrives.
      client.connection.add(_link(connected: false));
      await Future<void>.delayed(Duration.zero);
      client.connection.add(_link(connected: true));
      await Future<void>.delayed(Duration.zero);

      client.openGate();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        client.startStreamCalls,
        2,
        reason:
            'the reconnect needs a stream of its own; the one in flight was '
            'issued against the session that just ended',
      );
    },
  );

  // The headline behaviour of the reconnect handling, which #17 left without
  // coverage when it removed the test that drove the old requestSession API.
  test('a reconnect restarts the stream', () async {
    final client = _FakeClient()..connected = true;
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(client.startStreamCalls, 1);

    client.connection.add(_link(connected: false));
    await Future<void>.delayed(Duration.zero);
    client.connection.add(_link(connected: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(client.startStreamCalls, 2);
  });

  test('a reconnect during a failed open is still honoured', () async {
    final client = _FakeClient()
      ..connected = true
      ..failCalls = true
      ..gate = Completer<void>();
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    client.connection.add(_link(connected: false));
    await Future<void>.delayed(Duration.zero);
    client.connection.add(_link(connected: true));
    await Future<void>.delayed(Duration.zero);

    client.openGate();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      client.startStreamCalls,
      2,
      reason:
          'the attempt that failed was against the old session, so the '
          'reconnect still needs one of its own',
    );
  });

  test('one open runs at a time however many requests arrive', () async {
    final client = _FakeClient()
      ..connected = true
      ..gate = Completer<void>();
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 5; i++) {
      client.connection.add(_link(connected: true));
    }
    await Future<void>.delayed(Duration.zero);
    expect(client.startStreamCalls, 1, reason: 'still only the one in flight');

    client.openGate();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      client.startStreamCalls,
      2,
      reason:
          'five requests during one open ask for one more, not five - the '
          'guard is what keeps three RPCs per open from piling up',
    );
  });

  test('teardown stops the loop rather than finishing the open', () async {
    final client = _FakeClient()
      ..connected = true
      ..gate = Completer<void>();
    final session = RemoteSession(client: client);

    await Future<void>.delayed(Duration.zero);
    // A restart is queued behind the open that is still in flight.
    client.connection.add(_link(connected: false));
    await Future<void>.delayed(Duration.zero);
    client.connection.add(_link(connected: true));
    await Future<void>.delayed(Duration.zero);

    session.dispose();
    final atTeardown = client.openCalls;
    client.openGate();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      client.openCalls,
      atTeardown,
      reason:
          'the queued restart must not outlive the page - teardown has '
          'already run and _stopRemote latches, so nothing would undo it',
    );
  });

  // What the user actually sees, rather than a count of RPCs. Note which half
  // does it: a successful open is not enough, because the indicator tracks
  // frames arriving rather than RPCs landing - it drives a connection LED, and
  // lighting it green over a blank screen would say the wrong thing.
  test(
    'a frame clears the disconnected flag, a successful open does not',
    () async {
      final client = _FakeClient()..connected = true;
      final session = RemoteSession(client: client);
      addTearDown(session.dispose);

      await Future<void>.delayed(Duration.zero);
      client.connection.add(_link(connected: false));
      await Future<void>.delayed(Duration.zero);
      expect(session.isDisconnected, isTrue);

      client.connection.add(_link(connected: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        session.isDisconnected,
        isTrue,
        reason: 'the open having succeeded is not yet evidence frames flow',
      );

      client.broadcast.add(Main(guiScreenFrame: ScreenFrame()));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(session.isDisconnected, isFalse);
    },
  );

  // The priorities are the fix, not decoration. _stopRemote unsubscribes at
  // rightNow, and the queue sorts by priority before arrival - so a subscribe
  // left at the default is overtaken by the unsubscribe meant to undo it, and
  // the device is left pushing status that nothing listens to, with
  // _stopRemote already latched off.
  test(
    'the subscribe cannot be overtaken by the unsubscribe that undoes it',
    () async {
      final client = _FakeClient()..connected = true;
      final session = RemoteSession(client: client);

      await Future<void>.delayed(Duration.zero);
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final order = client.wireOrder;
      final subscribe = order.indexWhere(
        (r) => r.hasDesktopStatusSubscribeRequest(),
      );
      final unsubscribe = order.indexWhere(
        (r) => r.hasDesktopStatusUnsubscribeRequest(),
      );

      expect(subscribe, isNonNegative, reason: 'the open subscribes');
      expect(unsubscribe, isNonNegative, reason: 'teardown unsubscribes');
      expect(
        subscribe,
        lessThan(unsubscribe),
        reason:
            'a subscribe reaching the device after the unsubscribe leaves it '
            'pushing status for the rest of the connection',
      );
    },
  );

  /// A client whose IsLockedRequest answers [status]; everything else is OK.
  _FakeClient lockAnswering(CommandStatus status) => _FakeClient()
    ..connected = true
    ..statusFor = (request) =>
        request.hasDesktopIsLockedRequest() ? status : CommandStatus.OK;

  // #94. IsLockedRequest answers with an empty frame and puts the state in
  // command_status - OK locked, ERROR unlocked - so the generic handling turns
  // the ordinary case into a rejection. Before the fix that landed in _start's
  // catch and flagged the session disconnected over a screen that was
  // streaming perfectly.
  // _up is not async and guiSendInput resolves the session synchronously, so
  // before the Future.sync there the throw escaped past both the catchError
  // and the whenComplete that completes `sent` and calls onAnswer - stranding
  // the button's animation in the queue for the life of the page.
  test(
    'a release the session refuses outright still clears the button',
    () async {
      final client = _FakeClient()..connected = true;
      final session = RemoteSession(client: client);
      addTearDown(session.dispose);
      await Future<void>.delayed(Duration.zero);

      client.throwsSynchronously = true;
      await session.press(RemoteButton.ok);

      expect(
        session.queue,
        isEmpty,
        reason: 'the release answered, so the animation was dequeued',
      );
    },
  );

  test('an unlocked device does not read as a disconnected one', () async {
    final client = lockAnswering(CommandStatus.ERROR);
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await pumpEventQueue();

    expect(session.isDisconnected, isFalse);
  });

  // The direction of the mapping, which nothing else pins: every assertion
  // around it holds whether ERROR reads as locked or unlocked. Here the device
  // answered ERROR, so the baseline is already unlocked and a push saying the
  // same is not a transition. Read the other way round the baseline would be
  // locked and this would flash.
  test('ERROR is read as unlocked, not merely as not-a-failure', () async {
    final client = lockAnswering(CommandStatus.ERROR);
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);
    await pumpEventQueue();

    client.broadcast.add(Main()..desktopStatus = (Status()..locked = false));
    await pumpEventQueue();

    expect(session.justUnlocked, isFalse);
  });

  // The poll is the only way to learn the initial state at all, because a
  // subscribe never answers with it. Nothing consumed the answer before - the
  // frames loop could not match an empty frame - so the first lock-to-unlock
  // after opening had no baseline to flash against.
  test('the initial lock state is learned from the poll', () async {
    final client = lockAnswering(CommandStatus.OK);
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);
    await pumpEventQueue();

    client.broadcast.add(Main()..desktopStatus = (Status()..locked = false));
    await pumpEventQueue();

    expect(
      session.justUnlocked,
      isTrue,
      reason: 'locked was known, so unlocking is a transition worth flashing',
    );
  });

  // The baseline seeds, it does not announce. The poll's answer predates the
  // subscribe, and after a pause it is the first thing seen since - so an
  // unlock the user did on the device by hand would otherwise be reported
  // here as though it had just happened.
  test('the polled baseline does not flash an unlock', () async {
    final client = lockAnswering(CommandStatus.ERROR);
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);
    await pumpEventQueue();

    client.broadcast.add(Main()..desktopStatus = (Status()..locked = true));
    await pumpEventQueue();
    await session.pauseVisuals();
    await session.resumeVisuals();
    await pumpEventQueue();

    expect(session.justUnlocked, isFalse);
  });

  // OK alone means locked, so a firmware variant that did answer with a
  // status frame would otherwise be read as locked whatever it said.
  test('a status frame is preferred over what OK alone would mean', () async {
    final client = lockAnswering(CommandStatus.OK)
      ..framesFor = (request) => request.hasDesktopIsLockedRequest()
          ? [Main()..desktopStatus = (Status()..locked = false)]
          : const <Main>[];
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);
    await pumpEventQueue();

    client.broadcast.add(Main()..desktopStatus = (Status()..locked = false));
    await pumpEventQueue();

    expect(
      session.justUnlocked,
      isFalse,
      reason: 'the frame said unlocked, so the push is not a transition',
    );
  });

  // A status that is not ERROR still has to surface: swallowing every
  // rejection as "unlocked" would turn a real RPC failure into a lock state.
  // But it is not a disconnection either - the poll runs last, so the link has
  // already answered twice by then.
  test(
    'a status the firmware refuses is neither unlocked nor a drop',
    () async {
      final client = lockAnswering(CommandStatus.ERROR_NOT_IMPLEMENTED);
      final session = RemoteSession(client: client);
      addTearDown(session.dispose);
      await pumpEventQueue();

      expect(
        session.isDisconnected,
        isFalse,
        reason: 'the link answered twice',
      );

      client.broadcast.add(Main()..desktopStatus = (Status()..locked = false));
      await pumpEventQueue();

      expect(
        session.justUnlocked,
        isFalse,
        reason: 'no baseline was taken, so there is no transition to report',
      );
    },
  );
}
