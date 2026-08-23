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

  test('requestSession re-opens the stream and reports its progress', () async {
    final client = _FakeClient()..failCalls = true;
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(session.sessionBusy, isFalse);

    final future = session.requestSession();
    expect(session.sessionBusy, isTrue, reason: 'drives the spinner');
    await future;

    expect(session.sessionBusy, isFalse);
    expect(client.startStreamCalls, 2, reason: 'asked again on demand');
  });

  test('a concurrent request is ignored while one is in flight', () async {
    final client = _FakeClient();
    final session = RemoteSession(client: client);
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    final first = session.requestSession();
    final second = session.requestSession();
    await Future.wait([first, second]);

    expect(client.startStreamCalls, 2, reason: 'the open plus one request');
  });
}
