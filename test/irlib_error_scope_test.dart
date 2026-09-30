import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
// Not exported by the package root, and the chunked write reads it off the
// client to size its frames, so a fake has to answer it by name.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/tools/infrared/controller.dart';
import 'package:qunleashed/pages/tools/infrared/models.dart';

/// Which failures describe the list on screen, and which only describe what
/// the user last asked for.
///
/// The page renders its error view on `error != null && list.isEmpty`, and
/// every catch in the controller wrote to the same field. So a send that
/// failed while the listing was full rendered nothing - and then the next
/// search that matched nothing found that error still sitting there and
/// reported a disconnected Flipper as the reason a search came up empty,
/// with a Retry wired to re-listing the directory. #114.
class _UselessFlipper implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  Future<void> close() => _connection.close();

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Transport? get transport => null;

  @override
  bool isLinkDropError(Object e) => false;

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async => throw StateError('ERROR_STORAGE_NOT_READY');

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

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
  }) async => throw StateError('ERROR_STORAGE_NOT_READY');

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async => throw StateError('ERROR_STORAGE_NOT_READY');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IrEntry file(String name) =>
    IrEntry(name: name, path: 'TV/$name', type: IrEntryType.file);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _UselessFlipper client;
  late IrLibController ctrl;

  setUp(() {
    client = _UselessFlipper();
    ctrl = IrLibController(client: client);
    addTearDown(() async {
      ctrl.dispose();
      await client.close();
    });
  });

  group('a send the Flipper refused', () {
    test('is not offered as the reason a list is empty', () async {
      final sent = await ctrl.sendToFlipper(file('tv.ir'), const [1, 2, 3]);

      expect(sent, isFalse);
      expect(
        ctrl.error,
        isNull,
        reason: 'the listing is fine and still on screen',
      );
    });

    // The viewer's own message names no cause, so the reason has to be
    // somewhere it can reach.
    test('keeps its reason for the caller that shows a message', () async {
      await ctrl.sendToFlipper(file('tv.ir'), const [1, 2, 3]);

      expect(ctrl.lastFailure, contains('ERROR_STORAGE_NOT_READY'));
    });

    test('is nothing at all before anything is asked for', () {
      expect(ctrl.lastFailure, isNull);
      expect(ctrl.error, isNull);
    });
  });

  // readFileBytes goes the same way and is not covered here: its failure
  // comes from IrLibApi, which reaches raw.githubusercontent.com directly,
  // and a unit test that depends on a 404 from the internet is worse than no
  // test. The send above exercises the same two fields through the client.
}
