import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/logging.dart';

import 'archive_fakes.dart';
import 'kept_lines.dart';

/// What the archive does with an action whose device is not there.
///
/// Two gaps, both silent in a different way.
///
/// The delete was the expensive one. `_deleteKeys` gated the remote half on
/// `isConnected` and nothing else, so a link that was down - which for a bulk
/// delete over BLE is ordinary, and is the condition the sync loop's own
/// settle handling exists for - skipped the device half, deleted the local
/// copy anyway, and reported the whole thing as done. The file was still on
/// the Flipper and the next sync pulled it back, which is the shape a user
/// reports as "delete does not stick". Nothing was recorded at any level, so
/// the ratchets could not see it either: there was no call to count. #373.
///
/// The restore and save refusals were the cheap one. The *user* half of those
/// was covered already - `archive_failure_reason_test.dart` asserts a reason
/// reaches `lastFailure` - and what was missing was the record, so "restore
/// does nothing" arrived with no trace to read. #374.
///
/// The claims a ratchet cannot make, which is why they are here: that the
/// local half does **not** run when the device half could not, that a key
/// needing no link is not abandoned along with the link, that the key a drop
/// lands *on* is asked again rather than written off, that the queue stops
/// asking once the link is declared gone, that a device copy which did go is
/// not reported as "not deleted", and that what is kept is a locale- and
/// path-independent body rather than the sentence shown to the user.
class _DeletingFlipper with FlipperRpcFake, ArchiveRpcFake {
  bool connected = true;

  /// What [waitForRpcSession] answers - false is a link that never came back.
  bool sessionComesBack = true;

  /// The link goes down, without throwing, once this many deletes have been
  /// sent; -1 never. The drop a key meets *between* requests.
  int dropAfter = -1;

  /// Paths whose delete throws [LinkDropped] once each, then succeeds. The
  /// drop a key meets *inside* its own request.
  final Set<String> dropOnce = {};

  /// Paths whose delete always throws [LinkDropped].
  final Set<String> dropAlways = {};

  /// A path -> an error its delete always fails with. Not a link drop: these
  /// are the per-key failures the loop counts and carries on past.
  final Map<String, String> refuseDelete = {};

  /// Every path a delete was sent for, in order, retries included.
  final List<String> deletes = [];

  /// The timeout each wait was given, in order.
  final List<Duration> waitTimeouts = [];

  int get waits => waitTimeouts.length;

  @override
  bool get isConnected => connected;

  @override
  bool isLinkDropError(Object e) => e is LinkDropped;

  @override
  Future<bool> waitForRpcSession(Duration timeout) async {
    waitTimeouts.add(timeout);
    connected = sessionComesBack;
    return sessionComesBack;
  }

  @override
  List<Main> framesFor(Main request) {
    if (request.hasStorageDeleteRequest()) {
      final path = request.storageDeleteRequest.path;
      deletes.add(path);
      if (dropAlways.contains(path)) throw LinkDropped();
      // Once each: the retry has to be able to succeed, or the case would be
      // asserting on a permanently dead link rather than on a settle.
      if (dropOnce.remove(path)) throw LinkDropped();
      final refusal = refuseDelete[path];
      if (refusal != null) throw StateError(refusal);
      if (dropAfter >= 0 && deletes.length >= dropAfter) connected = false;
      return const [];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records which files the local half was asked to remove, and fails the ones
/// in [throwFor].
///
/// The call and not the file on disk: `hardDelete` is a no-op for a file that
/// is not there, so the only way to tell "asked and there was nothing" from
/// "never asked" is to watch the call. [throwFor] exists because the inverse
/// half-applied state - device copy gone, local copy still here, next upload
/// puts it back - is otherwise unreachable in a test.
class _RecordingStorage extends ArchiveStorage {
  final List<String> hardDeleted = [];
  final Set<String> throwFor = {};

  @override
  Future<void> hardDelete(
    String deviceName,
    ArchiveCategory cat,
    String fileName, {
    String? flipperDir,
    String subFolder = '',
  }) async {
    hardDeleted.add(fileName);
    if (throwFor.contains(fileName)) {
      // A real one, with the absolute path a real one carries: an assertion
      // about what the kept line may contain is worthless against a cause
      // that has no path in it.
      throw io.FileSystemException(
        'Deletion failed',
        '/data/user/0/app/files/archive/$deviceName/$fileName',
        const io.OSError('Permission denied', 13),
      );
    }
    await super.hardDelete(
      deviceName,
      cat,
      fileName,
      flipperDir: flipperDir,
      subFolder: subFolder,
    );
  }
}

const String _subghz = '/ext/subghz';

ArchiveKey key(String name, {bool deleted = false, bool onPhone = true}) =>
    ArchiveKey(
      name: name,
      category: ArchiveCategory.subghz,
      state: deleted ? ArchiveKeyState.deleted : ArchiveKeyState.synced,
      // What a non-null path buys is the local guard's `localPath != null`
      // disjunct - `inLocal` is false for every deleted key whatever the path
      // says. The local half is observed through [_RecordingStorage], not
      // through this path.
      localPath: onPhone ? '/phone/$name.sub' : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useTempArchiveRoot('archive_offline_actions');

  late _DeletingFlipper client;
  late _RecordingStorage storage;
  late ArchiveController ctrl;

  setUp(() {
    recordKeptLines();
    client = _DeletingFlipper();
    storage = _RecordingStorage();
    // No initialize(): the device name stays empty, which only makes the
    // refresh each action ends with return early. Everything asserted here
    // happens before it.
    ctrl = ArchiveController(client: client, storage: storage);
    addTearDown(() async {
      ctrl.dispose();
      await client.close();
    });
    clearKeptLines();
  });

  Iterable<String> lines(String fragment) =>
      keptLines.where((l) => l.contains(fragment));

  KeptLevel levelOf(String line) {
    final at = keptLines.indexOf(line);
    expect(at, isNonNegative, reason: 'nothing was kept matching: $line');
    return keptLevels[at];
  }

  /// Every kept line, joined - for asking what is in none of them.
  String everything() => keptLines.join('\n');

  group('a delete with the link down', () {
    test('waits out the settle and then deletes on both sides', () async {
      // Auto-reconnect is on with a 600ms settle, so a link that is down at
      // this instant is not a failed delete yet. The sync loop waits for the
      // same reason, and a delete of forty files meets a settle just as often.
      client.connected = false;

      await ctrl.deleteKeys([key('a')]);

      expect(client.deletes, ['$_subghz/a.sub']);
      expect(storage.hardDeleted, ['a.sub']);
      expect(ctrl.lastFailure, isNull, reason: 'it was deleted in the end');
      // A wait of no length is not a wait: the settle it exists for is 600ms,
      // so any timeout under a second makes the tolerance nothing at all.
      expect(
        client.waitTimeouts.single,
        greaterThan(const Duration(seconds: 1)),
      );
    });

    test('deletes neither half when the session stays down', () async {
      // The worked example from the issue, inverted into the invariant: a
      // delete asked for on both sides is all of it or none of it. Deleting
      // the local copy while the file stays on the Flipper is the state that
      // reads as success and comes back on the next sync.
      client.connected = false;
      client.sessionComesBack = false;

      await ctrl.deleteKeys([key('a')]);

      expect(client.deletes, isEmpty);
      expect(
        storage.hardDeleted,
        isEmpty,
        reason: 'the local copy is what keeps the two sides consistent',
      );
      expect(ctrl.lastFailure, contains('0 of 1'), reason: 'and it says so');
      // Which of the two summaries this is, and not merely that it carries
      // the right digits: the other one says the files were refused, when in
      // fact they were never asked for.
      expect(ctrl.lastFailure, contains('disconnected'));
    });

    test('still purges the keys that need no link', () async {
      // The loop skips a key it cannot delete on the device; it does not
      // abandon the queue. A deleted key behind a live one holds nothing on
      // the Flipper, so it is not waiting on a transport and has no reason to
      // be dropped along with one.
      client.connected = false;
      client.sessionComesBack = false;

      await ctrl.deleteKeys([key('live'), key('old', deleted: true)]);

      expect(client.deletes, isEmpty);
      expect(storage.hardDeleted, [
        'old.sub',
      ], reason: 'the live key is untouched, the purge still happens');
      expect(ctrl.lastFailure, contains('1 of 2'));
    });

    test('stops asking once the link is declared gone', () async {
      // Every remaining key would meet the same dead link, and the waiting is
      // what costs: one ten-second wait per key is minutes of an archive that
      // looks frozen. So the link is declared gone once and the rest skipped.
      client.dropAfter = 2;
      client.sessionComesBack = false;

      await ctrl.deleteKeys([key('a'), key('b'), key('c'), key('d')]);

      expect(client.deletes, ['$_subghz/a.sub', '$_subghz/b.sub']);
      expect(client.waits, 1, reason: 'once, not once per remaining key');
      expect(storage.hardDeleted, ['a.sub', 'b.sub']);
      expect(ctrl.lastFailure, contains('2 of 4'));

      final stopped = lines('delete stopped after').toList();
      expect(stopped, hasLength(1), reason: 'kept, so not at info');
      expect(stopped.single, contains('2 of 4'));
      expect(levelOf(stopped.single), KeptLevel.warning);
      // The sentence the user sees is localized; a kept body carrying it
      // groups as one issue per language.
      expect(stopped.single, isNot(contains(ctrl.lastFailure!)));
    });

    test('finishes the queue when a mid-queue settle comes back', () async {
      // The half the sync loop's own history warns about: `isLinkDropError`
      // is flipperlib's name for the fault a reconnect makes whole again, so
      // using it to abandon the queue ends a forty-file delete at whatever
      // key the settle happened to land on.
      client.dropAfter = 2;
      client.sessionComesBack = true;

      await ctrl.deleteKeys([key('a'), key('b'), key('c'), key('d')]);

      expect(client.deletes, hasLength(4), reason: 'all four were asked for');
      expect(storage.hardDeleted, ['a.sub', 'b.sub', 'c.sub', 'd.sub']);
      expect(ctrl.lastFailure, isNull);
      expect(lines('delete stopped after'), isEmpty);
    });
  });

  group("a drop inside one key's own request", () {
    test('asks for that key again after the settle', () async {
      // `storageDelete` has no restart of its own, so this request is lost -
      // but the queue is not. Without the retry the key the drop landed on
      // was the one key written off as a permanent failure, while every key
      // after it got the settle wait: backwards, because a settle lands
      // inside a request far more often than between two.
      client.dropOnce.add('$_subghz/b.sub');

      await ctrl.deleteKeys([key('a'), key('b'), key('c')]);

      expect(client.deletes, [
        '$_subghz/a.sub',
        '$_subghz/b.sub',
        '$_subghz/b.sub',
        '$_subghz/c.sub',
      ], reason: 'b was asked for twice and the rest of the queue still ran');
      expect(storage.hardDeleted, ['a.sub', 'b.sub', 'c.sub']);
      expect(ctrl.lastFailure, isNull, reason: 'nothing failed in the end');
    });

    test('keeps the local copy when the retry finds no session', () async {
      // One retry, not a loop. A second drop in the same breath is a link
      // that is not settling, and the queue stops there - the key after it
      // finds the link gone at its own check and is never attempted. What
      // matters per key is that the local copy of the one that failed stays:
      // it is the only thing left on the phone pointing at a file the device
      // may still hold.
      client.dropAlways.add('$_subghz/b.sub');
      client.sessionComesBack = false;

      await ctrl.deleteKeys([key('a'), key('b'), key('c')]);

      expect(storage.hardDeleted, [
        'a.sub',
      ], reason: 'b kept its local copy, and c was never attempted');
      expect(ctrl.lastFailure, contains('1 of 3'));
      expect(ctrl.lastFailure, contains('disconnected'));
      final stopped = lines('delete stopped after').toList();
      expect(stopped, hasLength(1));
      expect(
        stopped.single,
        contains('device'),
        reason: 'a report needs to know which half of the delete failed',
      );
      expect(
        stopped.single,
        contains('1 failed'),
        reason: 'the dropped key is counted, not only implied by the tail',
      );
    });
  });

  group('the delete summary', () {
    test('counts every cause instead of whichever was last', () async {
      // One slot held the last exception, so a card refusing thirty deletes
      // and a thirty-first failing benignly named the benign one. The two
      // causes here are distinct deliberately - with one cause a re-added
      // per-key line would fold into a single entry and the count assertion
      // below would pass whatever the shape.
      client.refuseDelete['$_subghz/a.sub'] = 'ERROR_STORAGE_DENIED';
      client.refuseDelete['$_subghz/b.sub'] = 'ERROR_STORAGE_INTERNAL';

      await ctrl.deleteKeys([key('a'), key('b'), key('c')]);

      expect(ctrl.lastFailure, contains('2 of 3'));
      expect(ctrl.lastFailure, contains('ERROR_STORAGE_DENIED'));
      expect(ctrl.lastFailure, contains('ERROR_STORAGE_INTERNAL'));
      expect(storage.hardDeleted, ['c.sub'], reason: 'a refusal stops its key');

      final summary = lines('delete:').toList();
      expect(summary, hasLength(1));
      expect(levelOf(summary.single), KeptLevel.warning);
    });

    test('says nothing per file, which is the burst the sync fixed', () async {
      // Positive absence, because the count assertion above cannot see this:
      // the per-key line this replaced said `delete failed: $e`, which shares
      // no substring with the summary. Re-adding it is a line per file again
      // - 94% of this project's entire outbound log volume, measured, and the
      // burst evicted real error events out of the SDK's cache.
      for (final name in ['a', 'b', 'c']) {
        client.refuseDelete['$_subghz/$name.sub'] = 'ERROR_STORAGE_DENIED';
      }

      await ctrl.deleteKeys([key('a'), key('b'), key('c')]);

      expect(lines('delete failed'), isEmpty);
      expect(
        everything(),
        isNot(contains(_subghz)),
        reason:
            'no file path in anything that ships: the cause groups, the path '
            'does not',
      );
      expect(lines('delete:'), hasLength(1));
    });

    test('does not call a file that went from the device undeleted', () async {
      // #373 inverted, and the worse direction: the device copy is gone, the
      // local one would not go, and the next upload puts the file back on the
      // card. Reporting that as "not deleted" sent the user to retry a delete
      // the device had already done.
      storage.throwFor.add('a.sub');

      await ctrl.deleteKeys([key('a')]);

      expect(client.deletes, ['$_subghz/a.sub'], reason: 'the device half ran');
      expect(ctrl.lastFailure, contains('not fully'));
      final summary = lines('delete:').toList();
      expect(summary, hasLength(1));
      expect(
        summary.single,
        contains('local'),
        reason: 'which half failed is the whole diagnosis here',
      );
      // A `FileSystemException` prints the absolute path it failed on, so a
      // tally keyed on it is one Sentry issue per file - and a path in a
      // toast. The OS code survives instead, which is what both readers need.
      expect(summary.single, contains('errno 13'));
      expect(summary.single, isNot(contains('/data/user')));
      expect(ctrl.lastFailure, isNot(contains('/data/user')));
    });

    test('counts only the keys it had something to do for', () async {
      // A key with no local copy, under "Delete local", has no half to run.
      // It used to reach the end of the loop and count as deleted, so the
      // numbers named files nothing was done to - "1 of 2" for a selection
      // whose second key was never touched. Observable only once something
      // fails, which is why the local half throws here.
      storage.throwFor.add('a.sub');

      await ctrl.deleteKeys(
        [key('a'), key('b', onPhone: false)],
        local: true,
        remote: false,
      );

      expect(storage.hardDeleted, ['a.sub'], reason: 'b has nothing to remove');
      expect(ctrl.lastFailure, contains('1 of 1'));
    });

    test('keeps the causes when the link then goes down', () async {
      // The branch that reports a stop appends the same tally, and this is
      // the case that says so: a refusal before the drop is a different fault
      // from the drop, and a stop that swallowed it would read as though the
      // disconnect were the only thing that happened.
      client.refuseDelete['$_subghz/a.sub'] = 'ERROR_STORAGE_DENIED';
      client.dropAfter = 2;
      client.sessionComesBack = false;

      await ctrl.deleteKeys([key('a'), key('b'), key('c')]);

      expect(ctrl.lastFailure, contains('disconnected'));
      expect(ctrl.lastFailure, contains('ERROR_STORAGE_DENIED'));
      final stopped = lines('delete stopped after').toList();
      expect(stopped, hasLength(1));
      expect(stopped.single, contains('ERROR_STORAGE_DENIED'));
      expect(
        stopped.single,
        contains('1 failed'),
        reason: 'the refusal is in the count, not only in the tail',
      );
    });
  });

  group('an action refused because nothing is connected', () {
    test('tells the user and keeps a line of its own', () async {
      client.connected = false;

      await ctrl.restoreKey(key('a', deleted: true));

      expect(ctrl.lastFailure, isNotNull, reason: 'the user half still works');
      final refused = lines('restore refused').toList();
      expect(refused, hasLength(1));
      // `caught`: a user pressing restore with no Flipper is ordinary, and
      // there is nothing for anyone to act on - but the rate of it says
      // whether the connection state is wrong.
      expect(levelOf(refused.single), KeptLevel.caught);
      expect(
        refused.single,
        isNot(contains(ctrl.lastFailure!)),
        reason: 'the localized sentence would group once per language',
      );
    });

    test('keeps a different line for each of the three', () async {
      // Three sites, three bodies. Two sharing one body are one issue in a
      // report - and `LogService` folds a consecutive identical body, so one
      // of the two can vanish outright.
      client.connected = false;

      await ctrl.restoreKey(key('a', deleted: true));
      await ctrl.restoreKeys([key('b', deleted: true)]);
      final saved = await ctrl.writeKeyBytes(key('a'), const [1, 2, 3]);

      expect(saved, isFalse);
      expect(keptLines.toSet(), hasLength(3), reason: 'no two sites share one');
      expect(lines('restore refused'), hasLength(1));
      expect(lines('restore selection refused'), hasLength(1));
      expect(lines('save refused'), hasLength(1));
    });

    test('says so when the copy on the phone is gone', () async {
      // The same symptom by a second route, one line below the refusal #374
      // names: `readBytes` answers null for a file that is not there rather
      // than throwing, so there was no catch to report from - the entry
      // stayed in the deleted list and nothing was said or kept.
      await ctrl.restoreKey(key('a', deleted: true));

      expect(ctrl.lastFailure, isNotNull);
      final missing = lines('no local copy').toList();
      expect(missing, hasLength(1));
      expect(levelOf(missing.single), KeptLevel.caught);
      expect(
        missing.single,
        contains('subghz'),
        reason:
            'the category, not the file name: forty files would be forty '
            'distinct bodies',
      );
    });
  });
}
