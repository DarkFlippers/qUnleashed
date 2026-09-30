import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/tools/paint/manager/controller.dart';
import 'package:qunleashed/pages/tools/paint/virtual_display_session.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// How long a failure in the Pixel Draw library lives, and who gets told.
///
/// The page shows the controller's error on every notification it makes, and
/// most of those are not failures - a tick of the weight slider is one. So a
/// failure that stayed put re-appeared on every tick, and one that was
/// cleared by the reload an operation ends with was never seen at all. #114.
class _OfflineFlipper implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  Future<void> close() => _connection.close();

  @override
  bool get isConnected => false;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A Flipper that is there and will not answer, which is what an import runs
/// into once the link is up but the storage is not.
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

  /// Answered as well as callRpcFrames, so the refusal the import meets is
  /// the one written above rather than a hole in this fake.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory root;
  late _OfflineFlipper client;
  late ProjectManagerController ctrl;

  setUpAll(() {
    // The library is a directory walk under the user's documents, which the
    // test process cannot otherwise move.
    root = io.Directory.systemTemp.createTempSync('paint_manager_failure');
    debugUseDocumentsRoot(root);
  });

  tearDownAll(() {
    debugUseDocumentsRoot(null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() {
    client = _OfflineFlipper();
    ctrl = ProjectManagerController(
      client: client,
      display: VirtualDisplaySession.instance,
    );
    addTearDown(() async {
      ctrl.dispose();
      await client.close();
    });
  });

  group('a failure waiting to be told', () {
    test('is there after the operation that caused it', () async {
      await ctrl.send();

      expect(ctrl.takeFailure(), isNotNull);
    });

    // The whole reason it is taken rather than read: the page's listener runs
    // on every notification, and most of them are not failures.
    test('is gone once it has been told', () async {
      await ctrl.send();
      expect(ctrl.takeFailure(), isNotNull);

      expect(ctrl.takeFailure(), isNull);
    });

    test('is nothing at all before anything fails', () {
      expect(ctrl.takeFailure(), isNull);
    });
  });

  group('the reload an operation ends with', () {
    // Delete sets a failure and never notifies; the silent reload after it
    // does. Clearing here is what threw the string away unread, and left the
    // project back in the list with nothing saying why.
    test('does not throw the failure away', () async {
      await ctrl.send();

      await ctrl.loadAll(silent: true);

      expect(ctrl.takeFailure(), isNotNull);
    });

    // A load the user asked for is a fresh question, so the last answer no
    // longer applies.
    test('does clear it when the user asked for the load', () async {
      await ctrl.send();

      await ctrl.loadAll();

      expect(ctrl.takeFailure(), isNull);
    });
  });

  group('an import that did not finish', () {
    // Zero is the answer that makes the page say "already up to date", and it
    // said it over the failure's own toast - which QNotification removes
    // outright rather than fading.
    test('answers null rather than nothing transferred', () async {
      expect(await ctrl.importFromDevice(), isNull);
    });

    test('still leaves the failure to be told', () async {
      await ctrl.importFromDevice();

      expect(ctrl.takeFailure(), isNotNull);
    });

    // The other way in, and the one the early return above cannot reach: the
    // link is up, the import starts, and the device will not answer.
    test('answers null when it started and then could not finish', () async {
      final useless = _UselessFlipper();
      final live = ProjectManagerController(
        client: useless,
        display: VirtualDisplaySession.instance,
      );
      addTearDown(() async {
        live.dispose();
        await useless.close();
      });

      expect(await live.importFromDevice(), isNull);
      expect(live.takeFailure(), contains('ERROR_STORAGE_NOT_READY'));
    });
  });
}
