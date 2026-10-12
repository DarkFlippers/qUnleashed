import 'dart:convert';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'archive_fakes.dart';
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
const _nfcRoot = '/ext/nfc';

class _SyncFlipper with ArchiveRpcFake {
  /// Directory path -> the entries it holds.
  final Map<String, List<fl.File>> tree = {};

  /// Remote path -> the bytes a read of it returns.
  final Map<String, String> bodies = {};

  /// Remote paths whose first read throws [LinkDropped], once each.
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

  @override
  bool isLinkDropError(Object e) => e is LinkDropped;

  @override
  Future<bool> waitForRpcSession(Duration timeout) async {
    waits += 1;
    return sessionComesBack;
  }

  @override
  List<Main> framesFor(Main request) {
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
      if (dropOnce.remove(path)) throw LinkDropped();
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late io.Directory root;
  late _SyncFlipper client;
  late ArchiveStorage storage;
  late ArchiveController ctrl;

  // ArchiveStorage caches its root in a static, so the root is set once for
  // the file and the device folder is rebuilt between cases.
  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('archive_sync_link_drop');
    debugUseDocumentsRoot(root);
    // The migration of the pre-Devices layout runs at the top of every
    // refresh and asks path_provider where the old folders were. Unanswered
    // it throws, and the whole refresh ends in the catch below it.
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
    // resolveRootDir caches into a static and every path getter asserts on
    // it, so it has to be awaited before the first deviceDir of the case.
    await storage.resolveRootDir();
    final device = storage.deviceDir(archiveTestDevice);
    if (device.existsSync()) device.deleteSync(recursive: true);
    await storage.writeLastDeviceName(archiveTestDevice);
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

  /// Four tags with the link dropping once on `b`, then a full sync.
  ///
  /// The arrange and act of three cases below, which were byte-identical and
  /// had to be edited in lockstep - the shape where one gets changed and the
  /// other silently stops testing what its name says. The cases stay separate
  /// because they make different claims; only the setup is shared.
  Future<void> syncWithDropOnB({bool comesBack = true}) async {
    fourTags();
    client.dropOnce.add('$_nfcRoot/b.nfc');
    client.sessionComesBack = comesBack;
    await ctrl.initialize();
    await ctrl.syncCategory(ArchiveCategory.nfc);
  }

  group('a link drop mid-sync', () {
    test('waits for the session and asks for the same file again', () async {
      // The predicate this branch stops on is flipperlib's own definition of
      // "a reconnect can fix this", and auto-reconnect is on. So the settle
      // is waited out and the file is retried, rather than the remaining
      // queue being abandoned for a fault the transport is already repairing.
      await syncWithDropOnB();

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
      await syncWithDropOnB(comesBack: false);

      expect(
        lines('read $_nfcRoot/b.nfc failed'),
        isEmpty,
        reason: 'not once per file, and not once in the summary either',
      );
      // What does ship is the shape: one line, naming the fault and how many
      // files met it. The path is deliberately absent - it varies per file
      // and the cause does not, which is what makes the line groupable in
      // Sentry rather than 2267 distinct messages.
      final stopped = lines('Sync stopped after').toList();
      expect(stopped, hasLength(1));
      expect(stopped.single, contains('Request dropped x1'));
      expect(
        stopped.single,
        isNot(contains(_nfcRoot)),
        reason: 'no file path in the one line that ships',
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
