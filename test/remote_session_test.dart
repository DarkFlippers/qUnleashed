import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
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
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    sent.add(_Sent(request, priority, sent.length));
    final held = gate;
    if (held != null) await held.future;
    if (failCalls) throw StateError('no active session');
    return const <Main>[];
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
}
