import 'package:flipperlib/flipperlib.dart' hide File;
// Not exported by the package root, and storageWriteChunked reads it off the
// client to size its frames, so a fake has to answer it by name.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/archive/browser/controller.dart';

/// Why an operation in the file manager failed, and how long that survives.
///
/// Every operation here already returns a bool, and the page already shows a
/// toast for it - "Delete failed", "Rename failed". What the toast could not
/// carry was the reason, because the only field holding it was `error`, and
/// `refresh()` nulls that. A refresh is the first thing that follows an
/// operation, so the page read the field after the one call guaranteed to
/// have emptied it. #110.
class _RefusingFlipper implements FlipperClient {
  /// Raised instead of answering anything but a listing, when set.
  Object? refuses;

  /// Raised instead of answering a listing, when set.
  Object? listRefuses;

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  /// A client with no transport is the state the app is in before a link
  /// comes up, and the only thing an upload reads it for is a frame size.
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
      if (listRefuses != null) throw listRefuses!;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RefusingFlipper client;
  late FileManagerController ctrl;

  setUp(() {
    client = _RefusingFlipper();
    ctrl = FileManagerController(client: client, initialPath: '/ext');
    addTearDown(ctrl.dispose);
  });

  group('the reason an operation failed', () {
    test('is what the device said', () async {
      client.refuses = StateError('ERROR_STORAGE_DENIED');

      expect(await ctrl.delete('/ext/keep.sub'), isFalse);
      expect(ctrl.lastFailure, contains('ERROR_STORAGE_DENIED'));
    });

    // The bug itself: a refresh is the first thing that follows an operation,
    // so a reason the refresh clears is one the page can never read.
    test('survives the refresh that follows the operation', () async {
      client.refuses = StateError('ERROR_STORAGE_DENIED');
      await ctrl.delete('/ext/keep.sub');

      await ctrl.refresh();

      expect(ctrl.lastFailure, contains('ERROR_STORAGE_DENIED'));
    });

    test('is replaced by the next failure, not added to', () async {
      client.refuses = StateError('ERROR_STORAGE_DENIED');
      await ctrl.delete('/ext/keep.sub');
      client.refuses = StateError('ERROR_STORAGE_NOT_READY');

      await ctrl.rename('/ext/a.sub', '/ext/b.sub');

      expect(ctrl.lastFailure, contains('ERROR_STORAGE_NOT_READY'));
      expect(ctrl.lastFailure, isNot(contains('DENIED')));
    });

    test('is nothing at all until something fails', () {
      expect(ctrl.lastFailure, isNull);
    });

    test('is not set by an operation that worked', () async {
      expect(await ctrl.delete('/ext/keep.sub'), isTrue);
      expect(ctrl.lastFailure, isNull);
    });
  });

  group('the listing error', () {
    // Unchanged, and deliberately the other way round: it describes what is
    // on screen now, so the next listing is meant to replace it.
    test('is still cleared by a refresh', () async {
      client.listRefuses = StateError('ERROR_STORAGE_NOT_READY');
      await ctrl.refresh();
      expect(ctrl.error, isNotNull);

      client.listRefuses = null;
      await ctrl.refresh();

      expect(ctrl.error, isNull);
    });

    // A listing that fails is not something the user asked for, and the panel
    // renders it for as long as it applies. Letting it through here would put
    // a stale reason on the next delete the user is told about.
    test('is not the reason an operation gets blamed for', () async {
      client.listRefuses = StateError('ERROR_STORAGE_NOT_READY');

      await ctrl.refresh();

      expect(ctrl.error, contains('ERROR_STORAGE_NOT_READY'));
      expect(ctrl.lastFailure, isNull);
    });
  });

  // The path the issue named: the page reads the reason, then refreshes, then
  // renders "Upload failed for 1 file(s): {reason}".
  group('an upload the device refused', () {
    test('still has its reason after the listing is rebuilt', () async {
      client.refuses = StateError('ERROR_STORAGE_FULL');

      expect(await ctrl.writeBytes('/ext/big.bin', const [1, 2, 3]), isFalse);
      final reason = ctrl.lastFailure;
      await ctrl.refresh();

      expect(reason, contains('ERROR_STORAGE_FULL'));
      expect(ctrl.lastFailure, reason);
      expect(ctrl.error, isNull, reason: 'which is why it could not be this');
    });
  });
}
