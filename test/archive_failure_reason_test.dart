import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
// Not exported by the package root, and storageWriteChunked reads it off the
// client to size its frames, so a fake has to answer it by name.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// Why a key the user acted on stayed where it was.
///
/// These operations return void, and the controller's `lastError` is cleared
/// by the refresh each of them ends with - so a delete the Flipper refused
/// used to reach nobody: the local copy went, the refresh re-listed the
/// remote file, and the key reappeared seconds later with no message. #110.
class _RefusingFlipper implements FlipperClient {
  /// Raised instead of answering, when set.
  Object? refuses;

  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  bool get isRpcReady => connected;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  Transport? get transport => null;

  @override
  bool isLinkDropError(Object e) => false;

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  @override
  String? getName() => 'TestFlipper';

  @override
  Future<String> awaitName() async => 'TestFlipper';

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    if (refuses != null) throw refuses!;
    await send((_) async {});
    return const [];
  }

  List<Main> _framesFor(Main request) {
    if (request.hasStorageListRequest()) {
      return [Main(storageListResponse: ListResponse())];
    }
    if (refuses != null) throw refuses!;
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
    final frames = _framesFor(request);
    for (final frame in frames) {
      onFrame?.call(frame);
    }
    return frames;
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = _framesFor(request);
    final items = <T>[];
    for (final frame in frames) {
      onFrame?.call(frame);
      final picked = pick(frame);
      if (picked != null) items.add(picked);
    }
    return FlipperRpcBatch<T>(
      commandId: 0,
      request: request,
      frames: frames,
      items: items,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ArchiveKey key({bool deleted = false, String? localPath}) => ArchiveKey(
  name: 'garage',
  category: ArchiveCategory.subghz,
  state: deleted ? ArchiveKeyState.deleted : ArchiveKeyState.synced,
  extension: '.sub',
  localPath: localPath,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory root;
  late _RefusingFlipper client;
  late ArchiveController ctrl;

  // ArchiveStorage caches its root in a static, so one root for the file and
  // an empty one between cases.
  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('archive_failure');
    debugUseDocumentsRoot(root);
  });

  tearDownAll(() {
    debugUseDocumentsRoot(null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() {
    client = _RefusingFlipper();
    // No initialize(): it adds a lifecycle observer and subscribes to two
    // client streams, none of which any of these operations touch. The device
    // name stays empty, which only makes the refresh at the end of each one
    // return early - the part that matters here is that it runs at all.
    ctrl = ArchiveController(client: client, storage: ArchiveStorage());
    addTearDown(ctrl.dispose);
  });

  group('the reason an action did not happen', () {
    // The worked example from the issue: the local copy goes, the refresh
    // re-lists the remote file, and the key is back with nothing said.
    test('is what the device said about a delete', () async {
      client.refuses = StateError('ERROR_STORAGE_DENIED');

      await ctrl.deleteKeys([key()]);

      expect(ctrl.lastFailure, contains('ERROR_STORAGE_DENIED'));
    });

    // The refresh at the end of every one of these is exactly what used to
    // empty the only field holding the reason.
    test('outlives the refresh the action ends with', () async {
      client.refuses = StateError('ERROR_STORAGE_DENIED');
      await ctrl.deleteKeys([key()]);

      await ctrl.refresh();

      expect(ctrl.lastFailure, contains('ERROR_STORAGE_DENIED'));
      expect(ctrl.lastError, isNull, reason: 'which is why it could not be it');
    });

    // Not an exception, and still the reason the action did not happen - so
    // the field has to carry more than a caught error.
    test('is the missing link when a restore has no Flipper', () async {
      client.connected = false;

      await ctrl.restoreKey(key(deleted: true));

      expect(ctrl.lastFailure, isNotNull);
    });

    test('is the same for a bulk restore with no Flipper', () async {
      client.connected = false;

      await ctrl.restoreKeys([key(deleted: true), key(deleted: true)]);

      expect(ctrl.lastFailure, isNotNull);
    });

    test('is nothing at all until something fails', () {
      expect(ctrl.lastFailure, isNull);
    });

    test(
      'is cleared by the next action rather than left to be re-shown',
      () async {
        client.refuses = StateError('ERROR_STORAGE_DENIED');
        await ctrl.deleteKeys([key()]);
        expect(ctrl.lastFailure, isNotNull);

        client.refuses = null;
        await ctrl.deleteKeys([key()]);

        expect(ctrl.lastFailure, isNull);
      },
    );
  });
}
