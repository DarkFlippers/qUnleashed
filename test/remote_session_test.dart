import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/desktop/session.dart';

class _FakeClient implements FlipperClient {
  final broadcast = StreamController<Main>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();
  final List<Main> requests = [];

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
    requests.add(request);
    final held = gate;
    if (held != null) await held.future;
    if (failCalls) throw StateError('no active session');
    return const <Main>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  FlipperConnectionState link({required bool connected}) =>
      FlipperConnectionState(
        mode: connected ? FlipperMode.rpc : FlipperMode.disconnected,
        device: null,
        connected: connected,
      );

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
      client.connection.add(link(connected: false));
      await Future<void>.delayed(Duration.zero);
      client.connection.add(link(connected: true));
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

    client.connection.add(link(connected: false));
    await Future<void>.delayed(Duration.zero);
    client.connection.add(link(connected: true));
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
    client.connection.add(link(connected: false));
    await Future<void>.delayed(Duration.zero);
    client.connection.add(link(connected: true));
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
      client.connection.add(link(connected: true));
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
}
