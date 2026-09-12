import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/infrared/local_repo.dart';

final String sep = Platform.pathSeparator;

/// A tree with one marker file, so which tree ended up where is visible.
Directory _treeAt(Directory dir, String marker) {
  dir.createSync(recursive: true);
  Directory('${dir.path}${sep}Brand').createSync(recursive: true);
  File('${dir.path}${sep}Brand${sep}tv.ir').writeAsStringSync(marker);
  return dir;
}

String _markerIn(Directory dir) =>
    File('${dir.path}${sep}Brand${sep}tv.ir').readAsStringSync();

void main() {
  late Directory base;
  late Directory root;
  late Directory incoming;

  setUp(() {
    base = Directory.systemTemp.createTempSync('ir_swap_test');
    root = Directory('${base.path}${sep}irlib');
    incoming = Directory('${root.path}.incoming');
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  /// Each swap names its own superseded tree, so tests look them up rather
  /// than assume a single fixed name.
  List<Directory> supersededTrees() => base
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.startsWith('${root.path}.superseded'))
      .toList();

  /// One left behind by an earlier run, with the shape a swap would give it.
  Directory stubSuperseded(String marker, {int at = 1000}) =>
      _treeAt(Directory('${root.path}.superseded.$at'), marker);

  /// Points the repo at the test's own root, and takes the teardown with it —
  /// a test that set the root and forgot to clear it would strand the next.
  void useRoot(Directory dir) {
    IrLibLocalRepo.debugUseRoot(dir);
    addTearDown(() => IrLibLocalRepo.debugUseRoot(null));
  }

  /// The superseded tree is deleted unawaited, so wait for it rather than
  /// guessing at a duration — it runs on the IO thread pool, where a loaded
  /// machine can miss any fixed delay.
  Future<void> waitUntilSwept() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (supersededTrees().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('superseded trees were still there after 5s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('swapping a new library in', () {
    test('the new tree replaces the old one', () async {
      _treeAt(root, 'old');
      _treeAt(incoming, 'new');

      await IrLibLocalRepo.swapIn(root, incoming);
      await waitUntilSwept();

      expect(_markerIn(root), 'new');
      expect(incoming.existsSync(), isFalse);
    });

    test('works when there was no library to replace', () async {
      _treeAt(incoming, 'new');

      await IrLibLocalRepo.swapIn(root, incoming);

      expect(_markerIn(root), 'new');
    });

    // The wedge: while every swap used one fixed name, a superseded tree that
    // could not be deleted - one locked file is enough, and a blocked
    // recursive delete removes what it reached before stopping - was the exact
    // path the next swap had to rename onto. Every later refresh then died
    // there, permanently, until someone found a hidden directory by hand. The
    // stub sits at that fixed name on purpose.
    test('a leftover at the old fixed name does not block the swap', () async {
      _treeAt(root, 'old');
      _treeAt(incoming, 'new');
      final stale = _treeAt(
        Directory('${root.path}.superseded'),
        'wedged an earlier run',
      );

      await IrLibLocalRepo.swapIn(root, incoming);

      expect(_markerIn(root), 'new');
      expect(
        stale.existsSync(),
        isTrue,
        reason: 'left for recovery to sweep, not renamed over',
      );
    });

    test('the old library is put back if the new one cannot move in', () async {
      _treeAt(root, 'old');

      await expectLater(
        IrLibLocalRepo.swapIn(root, incoming),
        throwsA(isA<FileSystemException>()),
      );

      expect(root.existsSync(), isTrue, reason: 'not left with nothing');
      expect(_markerIn(root), 'old');
    });

    // Not covered: the rollback inside swapIn failing, which is the moment a
    // strand is created mid-session. Reaching it needs something to occupy the
    // library path between the failed rename and the rollback, and there is no
    // await between them to hook — only a seam in the production code would
    // do it, which is a worse trade than the three lines it would cover.
    // download() recovers before it swaps, so it can never see the state the
    // swap creates. Without the swap clearing the record itself, the notice
    // sat under a button that by then read DELETE, still advising a download.
    test('a swap that lands clears a strand an earlier one left', () async {
      useRoot(root);
      final aside = stubSuperseded('stranded earlier');
      // A file where the library goes: the restore has nowhere to land, so
      // recovery keeps the tree and records it.
      File(root.path).writeAsStringSync('in the way');
      await IrLibLocalRepo.recoverInterrupted(root);
      expect(
        IrLibLocalRepo.strandedLibrary.value?.path,
        aside.path,
        reason: 'the strand this test is about',
      );

      // Cleared before the swap, so nothing recovers on the way past - the
      // swap itself is the only thing that can clear the record here.
      File(root.path).deleteSync();
      _treeAt(incoming, 'new');
      await IrLibLocalRepo.swapIn(root, incoming);

      expect(_markerIn(root), 'new');
      expect(IrLibLocalRepo.strandedLibrary.value, isNull);
    });
  });

  group('recovering an interrupted refresh', () {
    test('an unpack that never finished is cleared', () async {
      _treeAt(root, 'old');
      _treeAt(incoming, 'half done');

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(incoming.existsSync(), isFalse);
      expect(_markerIn(root), 'old');
    });

    // The one window that loses data: the library has been moved aside and
    // its replacement is not in place yet.
    test(
      'a swap that died between the two renames puts the library back',
      () async {
        stubSuperseded('old');
        expect(root.existsSync(), isFalse);

        await IrLibLocalRepo.recoverInterrupted(root);

        expect(_markerIn(root), 'old');
        expect(supersededTrees(), isEmpty);
      },
    );

    test('the newest tree is the one put back', () async {
      stubSuperseded('older', at: 1000);
      stubSuperseded('the one that was live', at: 2000);

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(_markerIn(root), 'the one that was live');
      expect(supersededTrees(), isEmpty, reason: 'the older one is swept');
    });

    test(
      'a delete that never finished is cleared, library left alone',
      () async {
        _treeAt(root, 'current');
        stubSuperseded('stale');

        await IrLibLocalRepo.recoverInterrupted(root);

        expect(_markerIn(root), 'current');
        expect(supersededTrees(), isEmpty);
      },
    );

    test('does nothing when there is nothing to repair', () async {
      _treeAt(root, 'current');

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(_markerIn(root), 'current');
    });

    test('is safe when there is no library at all', () async {
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(root.existsSync(), isFalse);
    });

    // A restore that cannot land leaves that tree holding the only copy of the
    // library there is. Clearing it then — which the first version did, with
    // no condition — turns a recoverable interruption into the loss recovery
    // exists to prevent.
    test('a library that cannot be put back is kept, not cleared', () async {
      final stub = stubSuperseded('the only copy');
      File(root.path).writeAsStringSync('in the way');

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(stub.existsSync(), isTrue);
      expect(_markerIn(stub), 'the only copy');
    });
  });

  group('what a refresh does before it fetches anything', () {
    // #62 in one assertion. download() reaches getTemporaryDirectory, which
    // has no plugin in a unit test, so it fails in the window the old code had
    // already deleted the library in.
    test('a refresh that fails early leaves the library standing', () async {
      _treeAt(root, 'old');
      useRoot(root);

      await expectLater(
        IrLibLocalRepo().download(owner: 'o', repo: 'r', branch: 'b'),
        throwsA(anything),
      );

      expect(_markerIn(root), 'old');
      expect(
        incoming.existsSync(),
        isTrue,
        reason: 'staged beside the library rather than over it',
      );
    });

    test('the staging tree is cleared by the next recovery', () async {
      _treeAt(root, 'old');
      useRoot(root);

      await expectLater(
        IrLibLocalRepo().download(owner: 'o', repo: 'r', branch: 'b'),
        throwsA(anything),
      );
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(incoming.existsSync(), isFalse);
      expect(_markerIn(root), 'old');
    });

    // Deleting the library first leaves root missing while a superseded tree
    // stands, which is indistinguishable from an interrupted swap — so an
    // interrupted delete used to hand the previous library back.
    test('a delete cannot resurrect the previous library', () async {
      _treeAt(root, 'current');
      stubSuperseded('previous');
      useRoot(root);

      await IrLibLocalRepo().deleteAll();
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(root.existsSync(), isFalse, reason: 'the delete stays done');
      expect(supersededTrees(), isEmpty);
    });

    // Two pages mean two repos over one set of process-wide directories.
    // Queued, the second refresh cannot delete the staging tree the first is
    // unpacking into.
    test('two refreshes queue rather than collide', () async {
      _treeAt(root, 'old');
      useRoot(root);

      final outcomes = await Future.wait([
        IrLibLocalRepo()
            .download(owner: 'a', repo: 'r', branch: 'b')
            .then<Object?>((d) => d)
            .onError<Object>((e, _) => e),
        IrLibLocalRepo()
            .download(owner: 'b', repo: 'r', branch: 'b')
            .then<Object?>((d) => d)
            .onError<Object>((e, _) => e),
      ]);

      expect(
        outcomes.whereType<Directory>(),
        isEmpty,
        reason: 'both failed on their own, neither on the other',
      );
      expect(_markerIn(root), 'old');
    });
  });
}
