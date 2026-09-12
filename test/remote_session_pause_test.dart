import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/remote/desktop/session.dart';

class _PauseFakeClient implements FlipperClient {
  final broadcast = StreamController<Main>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();
  final List<Main> requests = [];

  bool connected = false;
  Completer<void>? startGate;

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
    if (request.hasGuiStartScreenStreamRequest()) {
      final gate = startGate;
      if (gate != null) await gate.future;
    }
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

  test('shutdown immediately removes wrist input availability', () async {
    final client = _PauseFakeClient()..connected = true;
    final session = RemoteSession(client: client);

    await Future<void>.delayed(Duration.zero);
    expect(session.inputAvailable, isTrue);

    session.shutdown();

    expect(
      session.inputAvailable,
      isFalse,
      reason: 'a page in its exit transition must advertise no wrist input',
    );
    session.dispose();
  });

  test(
    'reconnect while paused restores input but not the visual connected flag',
    () async {
      final client = _PauseFakeClient()..connected = true;
      final session = RemoteSession(client: client);
      addTearDown(session.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.startStreamCalls, 1);
      expect(session.inputAvailable, isTrue);

      await session.pauseVisuals();

      client.connected = false;
      client.connection.add(_link(connected: false));
      await Future<void>.delayed(Duration.zero);
      expect(session.inputAvailable, isFalse);
      expect(session.isDisconnected, isTrue);

      client.connected = true;
      client.connection.add(_link(connected: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(session.inputAvailable, isTrue);
      expect(
        session.isDisconnected,
        isTrue,
        reason: 'an RPC reconnect is not evidence that framebuffer data flows',
      );
      expect(
        client.startStreamCalls,
        1,
        reason: 'visual streams stay paused in the background',
      );

      await session.resumeVisuals();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.startStreamCalls, 2);
      expect(session.isDisconnected, isTrue);

      client.broadcast.add(Main(guiScreenFrame: ScreenFrame()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.isDisconnected, isFalse);
    },
  );

  test(
    'pause during an in-flight open resumes with one fresh stream',
    () async {
      final client = _PauseFakeClient()
        ..connected = true
        ..startGate = Completer<void>();
      final session = RemoteSession(client: client);
      addTearDown(session.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(client.startStreamCalls, 1);

      await session.pauseVisuals();
      client.startGate!.complete();
      client.startGate = null;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await session.resumeVisuals();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        client.startStreamCalls,
        2,
        reason: 'the paused in-flight open is abandoned and resume opens once',
      );
    },
  );
}
