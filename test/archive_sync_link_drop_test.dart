import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'kept_lines.dart';

/// What a sync does when the link dies part way through it.
///
/// None of this was covered, and the whole of the first commit on this branch
/// lives here: the per-file line that was 94% of the project's outbound log
/// volume, the decision to stop rather than ask a dead transport for two
/// thousand more files, the number the summary reports, and the level it
/// reports at. A ratchet cannot see any of them - `caught_budget_test.dart`
/// counts call sites and `logErrors: false` removes none, and
/// `log_level_budget_test.dart` only counts `info` inside a catch clause,
/// which the summary is not in. So reverting any of it was green.
///
/// The retry is the part that needed a test most, because the first version of
/// this branch got it backwards. `isLinkDropError` is defined in flipperlib as
/// the class of failure "an automatic reconnect can make whole again", and
/// `storageWriteChunked` acts on exactly that - it waits for the session and
/// restarts the upload. Using the same predicate to *abandon* a sync meant a
/// 600ms reconnect settle, which is ordinary on BLE, ended a whole-card sync
/// at whatever file it happened to reach.
const _device = 'TestFlipper';
const _nfcRoot = '/ext/nfc';

class _LinkDropped implements Exception {
  @override
  String toString() => 'Bad state: Request dropped';
}

class _SyncFlipper implements FlipperClient {
  /// Directory path -> the entries it holds.
  final Map<String, List<fl.File>> tree = {};

  /// Remote path -> the bytes a read of it returns.
  final Map<String, String> bodies = {};

  /// Remote paths whose first read throws [_LinkDropped], once each.
  final Set<String> dropOnce = {};

  /// Remote path -> an RPC status its read always fails with.
  ///
  /// Not a link drop: these are the per-file failures the loop is supposed to
  /// count and carry on past, which is what distinguishes the two branches.
  final Map<String, String> refuseRead = {};

  /// What [waitForRpcSession] answers - false is a link that never came back.
  bool sessionComesBack = true;

  /// Every path a read was attempted for, in order, retries included.
  final List<String> reads = [];

  /// How many times the loop waited for a session.
  int waits = 0;

  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _info = StreamController<Map<String, String>>.broadcast();

  Future<void> close() async {
    await _connection.close();
    await _info.close();
  }

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _info.stream;

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  String? getName() => _device;

  @override
  Future<String> awaitName() async => _device;

  @override
  bool isLinkDropError(Object e) => e is _LinkDropped;

  @override
  Future<bool> waitForRpcSession(Duration timeout) async {
    waits += 1;
    return sessionComesBack;
  }

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  List<Main> _framesFor(Main request) {
    if (request.hasStorageListRequest()) {
      final path = request.storageListRequest.path;
      return [
        Main(
          storageListResponse: ListResponse()
            ..file.addAll(tree[path] ?? const []),
        ),
      ];
    }
    if (request.hasStorageReadRequest()) {
      final path = request.storageReadRequest.path;
      reads.add(path);
      // Once each: the retry has to be able to succeed, or the test would be
      // asserting on a permanently dead link rather than on a settle.
      if (dropOnce.remove(path)) throw _LinkDropped();
      final refusal = refuseRead[path];
      if (refusal != null) throw StateError(refusal);
      final body = bodies[path];
      if (body == null) return const [];
      return [
        Main(
          storageReadResponse: ReadResponse(
            file: fl.File(data: utf8.encode(body)),
          ),
        ),
      ];
    }
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

fl.File tag(String name) =>
    fl.File(name: name, type: File_FileType.FILE, size: 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late io.Directory root;
  late _SyncFlipper client;
  late ArchiveStorage storage;
  late ArchiveController ctrl;

  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('archive_sync_link_drop');
    debugUseDocumentsRoot(root);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '${root.path}${io.Platform.pathSeparator}legacy',
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    debugUseDocumentsRoot(null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() async {
    client = _SyncFlipper();
    storage = ArchiveStorage();
    await storage.resolveRootDir();
    final device = storage.deviceDir(_device);
    if (device.existsSync()) device.deleteSync(recursive: true);
    await storage.writeLastDeviceName(_device);
    ctrl = ArchiveController(client: client, storage: storage);
    clearKeptLines();
    addTearDown(() async {
      ctrl.dispose();
      await client.close();
    });
  });

  /// Four NFC tags on the device and nothing on the phone, so a sync has four
  /// files to fetch in a known order.
  void fourTags() {
    client.tree[_nfcRoot] = [
      tag('a.nfc'),
      tag('b.nfc'),
      tag('c.nfc'),
      tag('d.nfc'),
    ];
    for (final name in ['a', 'b', 'c', 'd']) {
      client.bodies['$_nfcRoot/$name.nfc'] =
          'Filetype: Flipper NFC device\nUID: 00 01 02 03\n';
    }
  }

  Iterable<String> lines(String fragment) =>
      keptLines.where((l) => l.contains(fragment));

  group('a link drop mid-sync', () {
    test('waits for the session and asks for the same file again', () async {
      // The predicate this branch stops on is flipperlib's own definition of
      // "a reconnect can fix this", and auto-reconnect is on. So the settle
      // is waited out and the file is retried, rather than the remaining
      // queue being abandoned for a fault the transport is already repairing.
      fourTags();
      client.dropOnce.add('$_nfcRoot/b.nfc');

      await ctrl.initialize();
      await ctrl.syncCategory(ArchiveCategory.nfc);

      expect(client.waits, 1, reason: 'it waited once, for the one drop');
      expect(
        client.reads,
        containsAllInOrder([
          '$_nfcRoot/b.nfc',
          '$_nfcRoot/b.nfc',
          '$_nfcRoot/c.nfc',
          '$_nfcRoot/d.nfc',
        ]),
        reason: 'b was retried and the rest of the queue still ran',
      );
      expect(ctrl.lastFailure, isNull, reason: 'nothing failed in the end');
      expect(lines('Sync stopped after'), isEmpty);
    });

    test(
      'stops, and says the rest was never asked for, when it stays down',
      () async {
        // The other half. A session that does not come back ends the sync -
        // every remaining file would fail instantly against a dead transport,
        // which is the 2267-entry burst this branch exists to stop.
        fourTags();
        client.dropOnce.add('$_nfcRoot/b.nfc');
        client.sessionComesBack = false;

        await ctrl.initialize();
        await ctrl.syncCategory(ArchiveCategory.nfc);

        expect(client.waits, 1);
        expect(client.reads, [
          '$_nfcRoot/a.nfc',
          '$_nfcRoot/b.nfc',
        ], reason: 'c and d were never asked for');
        // The number is the queue, not what the loop reached. Reporting what it
        // reached read "Downloaded 1/2; 1 failed" for a sync of four - tidy,
        // and a claim that it finished.
        final stopped = lines('Sync stopped after');
        expect(stopped, isNotEmpty, reason: 'and it is kept, so not at info');
        expect(stopped.single, contains('2 of 4'));
        // `lastFailure` and not only `lastError`: on the common path - pull to
        // refresh, a non-empty category - `lastError` is rendered nowhere, so a
        // truncated sync would otherwise just look finished.
        expect(ctrl.lastFailure, contains('2 of 4'));
      },
    );

    test('says nothing per file, which was 94% of all log volume', () async {
      // `logErrors: false`. The flood, measured: 2267 entries from one sync,
      // and the burst evicted two of the three error events captured that day
      // out of the SDK's envelope cache. Nothing static can see this - the
      // call site is still there, its body just does not run - so this
      // assertion is the only thing standing between here and a revert.
      fourTags();
      client.dropOnce.add('$_nfcRoot/b.nfc');
      client.sessionComesBack = false;

      await ctrl.initialize();
      await ctrl.syncCategory(ArchiveCategory.nfc);

      final mentions = lines('read $_nfcRoot/b.nfc failed').toList();
      expect(
        mentions,
        hasLength(1),
        reason: 'once, in the summary - not once per file',
      );
      expect(
        mentions.single,
        contains('Sync stopped after'),
        reason: 'and that one mention is the summary, not a per-file line',
      );
    });
  });

  group('the sync summary', () {
    test('counts the queue and names the causes', () async {
      // A plain failure with the link up: no drop, so the loop runs the whole
      // queue and the tally is the ordinary one. The cause count is what
      // replaced the per-file lines - a single `_lastReadError` slot would
      // report whichever failure was last, so forty files failing on a
      // corrupting card and a benign forty-first would report the benign one.
      client.tree[_nfcRoot] = [tag('a.nfc'), tag('b.nfc'), tag('c.nfc')];
      client.bodies['$_nfcRoot/c.nfc'] = 'Filetype: Flipper NFC device\n';
      // Two distinct causes, which is the point: one slot would report
      // whichever came last.
      client.refuseRead['$_nfcRoot/a.nfc'] = 'ERROR_STORAGE_INTERNAL';
      client.refuseRead['$_nfcRoot/b.nfc'] = 'ERROR_STORAGE_DENIED';

      await ctrl.initialize();
      await ctrl.syncCategory(ArchiveCategory.nfc);

      final summary = lines('Downloaded').toList();
      expect(summary, hasLength(1), reason: 'kept, so not at info');
      expect(
        summary.single,
        contains('/3'),
        reason: 'the queue is the denominator',
      );
      expect(summary.single, contains('ERROR_STORAGE_INTERNAL'));
      expect(
        summary.single,
        contains('ERROR_STORAGE_DENIED'),
        reason: 'both causes, not just the last one',
      );
      expect(client.waits, 0, reason: 'no link drop, so no waiting');
    });
  });
}
