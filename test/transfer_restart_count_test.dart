// An upload that restarts says so — ADR 0013 §2 asks for the count by name.
//
// `autoReconnect` is on and `client/api/storage.dart` restarts a write from
// offset 0 when the link drops and the session is restored — **exactly once**,
// because the firmware opens the file with CREATE_ALWAYS so a restart from
// zero is safe. `onProgress` is driven from `offset / total`, so the restart
// shows as progress falling back. That is the only signal on the app's side:
// the restart happens inside the library and is not announced through the
// callback.
//
// Which makes the count worth a test rather than a comment, because the
// heuristic is about somebody else's code. This drives the real
// `storageWriteChunked` through a fake that drops the link mid-stream, so the
// restart is the library's own rather than a simulation of it.
import 'package:flipperlib/flipperlib.dart' hide File;
// Not exported by the package root, and storageWriteChunked reads it off the
// client to size its frames, so a fake has to answer it by name. Prefixed
// because the Sentry SDK has a `Transport` of its own and this file needs
// both.
import 'package:flipperlib/src/transport/transport.dart' as flipper;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/controller.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'kept_lines.dart';

import 'sentry_capture.dart';

/// Raised by [_DroppingFlipper] to look like a lost link.
class _LinkDropped implements Exception {
  @override
  String toString() => 'link dropped';
}

/// A client that loses the link once, part way through the first upload.
class _DroppingFlipper implements FlipperClient {
  /// How many frames to accept before the link goes, on the first attempt.
  int dropAfterFrames = 2;

  /// Refuses every attempt, for the failed-transfer case.
  bool refuseAlways = false;

  /// Attempts seen, so the drop happens once and the retry succeeds.
  int attempts = 0;

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  /// A client with no transport is the state the app is in before a link comes
  /// up, and the only thing an upload reads it for is a frame size.
  @override
  flipper.Transport? get transport => null;

  @override
  bool isLinkDropError(Object e) => e is _LinkDropped;

  @override
  Future<bool> waitForRpcSession(Duration timeout) async => true;

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    attempts += 1;
    if (refuseAlways) throw StateError('ERROR_STORAGE_FULL');
    final failing = attempts == 1;
    var frames = 0;
    await send((_) async {
      frames += 1;
      if (failing && frames > dropAfterFrames) throw _LinkDropped();
    });
    return const [];
  }

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
  }) async {
    if (request.hasStorageListRequest()) {
      return [Main(storageListResponse: ListResponse())];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(recordKeptLines);

  late _DroppingFlipper client;
  late FileManagerController ctrl;
  late List<SentryTransaction> sent;

  setUp(() async {
    clearKeptLines();
    client = _DroppingFlipper();
    ctrl = FileManagerController(client: client, initialPath: '/ext');
    sent = await captureTransactions();
  });

  tearDown(() async {
    await Sentry.close();
    clearKeptLines();
  });

  Future<bool> write(int bytes) =>
      ctrl.writeBytes('/ext/big.bin', List.filled(bytes, 7));

  test('a write interrupted by a link drop still succeeds', () async {
    // The precondition for the count meaning anything: the library really does
    // restart rather than fail, so the caller sees one successful transfer.
    expect(await write(8192), isTrue);
    expect(client.attempts, 2, reason: 'dropped once, then restarted');
  });

  test('the span counts the restart', () async {
    await write(8192);
    await Sentry.close();

    expect(sent, hasLength(1));
    expect(sent.single.data['restarts'], 1);
  });

  test('a write nobody interrupted counts none', () async {
    // The other half. Without it a counter that fired on every progress
    // callback would pass the test above.
    client.dropAfterFrames = 1 << 30;

    await write(8192);
    await Sentry.close();

    expect(client.attempts, 1);
    expect(
      sent.single.data.containsKey('restarts'),
      isFalse,
      reason: 'absent rather than zero - the key appears when it happens',
    );
  });

  test('the path is scrubbed and the size is not', () async {
    await write(2048);
    await Sentry.close();

    final data = sent.single.data;
    expect(
      data['path'],
      '/ext/<name>.bin',
      reason: 'the directory and the extension stay, the filename does not',
    );
    expect(data['bytes'], 2048);
  });

  test('a refused write marks the operation failed', () async {
    // `writeBytes` catches and answers false, so without `trace.failed()` this
    // would arrive as a successful transfer.
    client.refuseAlways = true;

    expect(await write(2048), isFalse);
    await Sentry.close();

    expect(sent.single.status, 'internal_error');
  });
}
