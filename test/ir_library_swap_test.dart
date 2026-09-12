import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/infrared/local_repo.dart';

final String sep = Platform.pathSeparator;

void main() {
  late Directory base;
  late Directory root;
  late Directory incoming;
  late Directory superseded;

  setUp(() {
    base = Directory.systemTemp.createTempSync('ir_swap_test');
    root = Directory('${base.path}${sep}irlib');
    incoming = Directory('${root.path}.incoming');
    superseded = Directory('${root.path}.superseded');
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  /// A tree with one marker file, so which tree ended up where is visible.
  Directory treeAt(Directory dir, String marker) {
    dir.createSync(recursive: true);
    Directory('${dir.path}${sep}Brand').createSync(recursive: true);
    File('${dir.path}${sep}Brand${sep}tv.ir').writeAsStringSync(marker);
    return dir;
  }

  String markerIn(Directory dir) =>
      File('${dir.path}${sep}Brand${sep}tv.ir').readAsStringSync();

  /// The delete of the superseded tree is deliberately not awaited, so wait
  /// for it rather than guessing at a duration - it runs on the IO thread
  /// pool, where a loaded machine can miss any fixed delay.
  Future<void> waitGone(Directory dir) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (dir.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('${dir.path} was still there after 5s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('swapping a new library in', () {
    test('the new tree replaces the old one', () async {
      treeAt(root, 'old');
      treeAt(incoming, 'new');

      await IrLibLocalRepo.swapIn(root, incoming);
      await waitGone(superseded);

      expect(markerIn(root), 'new');
      expect(incoming.existsSync(), isFalse);
    });

    test('works when there was no library to replace', () async {
      treeAt(incoming, 'new');

      await IrLibLocalRepo.swapIn(root, incoming);
      await waitGone(superseded);

      expect(markerIn(root), 'new');
    });

    test('a leftover superseded tree does not block the swap', () async {
      treeAt(root, 'old');
      treeAt(incoming, 'new');
      treeAt(superseded, 'older still');

      await IrLibLocalRepo.swapIn(root, incoming);
      await waitGone(superseded);

      expect(markerIn(root), 'new');
    });

    test('the old library is put back if the new one cannot move in', () async {
      treeAt(root, 'old');
      // No incoming at all: the second rename fails, and the library has
      // already been moved aside by then.
      await expectLater(
        IrLibLocalRepo.swapIn(root, incoming),
        throwsA(isA<FileSystemException>()),
      );

      expect(root.existsSync(), isTrue, reason: 'not left with nothing');
      expect(markerIn(root), 'old');
    });
  });

  group('recovering an interrupted refresh', () {
    test('an unpack that never finished is cleared', () async {
      treeAt(root, 'old');
      treeAt(incoming, 'half done');

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(incoming.existsSync(), isFalse);
      expect(markerIn(root), 'old', reason: 'the library is untouched');
    });

    // The one window that loses data: the old tree has been moved aside and
    // the new one is not in place yet.
    test(
      'a swap that died between the two renames puts the library back',
      () async {
        treeAt(superseded, 'old');
        expect(root.existsSync(), isFalse);

        await IrLibLocalRepo.recoverInterrupted(root);

        expect(root.existsSync(), isTrue);
        expect(markerIn(root), 'old');
        expect(superseded.existsSync(), isFalse);
      },
    );

    test(
      'a delete that never finished is cleared, library left alone',
      () async {
        treeAt(root, 'current');
        treeAt(superseded, 'stale');

        await IrLibLocalRepo.recoverInterrupted(root);

        expect(markerIn(root), 'current');
        expect(superseded.existsSync(), isFalse);
      },
    );

    test('does nothing when there is nothing to repair', () async {
      treeAt(root, 'current');

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(markerIn(root), 'current');
    });

    test('is safe when there is no library at all', () async {
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(root.existsSync(), isFalse);
    });
  });

  group('the states review found unguarded', () {
    // The restore failing leaves .superseded holding the only copy there is.
    // Deleting it then - which the first version did, unconditionally - turns
    // a recoverable interruption into the loss it was there to prevent.
    test('a library that cannot be put back is kept, not cleared', () async {
      treeAt(superseded, 'the only copy');
      // A file where the library goes: the rename cannot land.
      File(root.path).writeAsStringSync('in the way');

      await IrLibLocalRepo.recoverInterrupted(root);

      expect(
        Directory(superseded.path).existsSync(),
        isTrue,
        reason: 'the last copy of the library must survive a failed restore',
      );
      expect(markerIn(superseded), 'the only copy');
    });

    // Deleting the library first leaves root missing while .superseded stands,
    // which is indistinguishable from an interrupted swap - so an interrupted
    // delete used to hand the previous library back.
    test('a part-finished delete cannot resurrect the old library', () async {
      treeAt(root, 'current');
      treeAt(superseded, 'previous');
      IrLibLocalRepo.debugUseRoot(root);
      addTearDown(() => IrLibLocalRepo.debugUseRoot(null));

      await IrLibLocalRepo().deleteAll();
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(root.existsSync(), isFalse, reason: 'the delete stays done');
      expect(superseded.existsSync(), isFalse);
    });
  });

  group('what a refresh does before it fetches anything', () {
    // #62 in one assertion. download() reaches getTemporaryDirectory, which
    // has no plugin in a unit test, so it fails in the window the old code
    // had already deleted the library in.
    test('a refresh that fails early leaves the library standing', () async {
      treeAt(root, 'old');
      IrLibLocalRepo.debugUseRoot(root);
      addTearDown(() => IrLibLocalRepo.debugUseRoot(null));

      await expectLater(
        IrLibLocalRepo().download(owner: 'o', repo: 'r', branch: 'b'),
        throwsA(anything),
      );

      expect(
        markerIn(root),
        'old',
        reason: 'the library is untouched until there is a replacement',
      );
      expect(
        incoming.existsSync(),
        isTrue,
        reason: 'staged beside the library rather than over it',
      );
    });

    test('the staging tree is cleared by the next recovery', () async {
      treeAt(root, 'old');
      IrLibLocalRepo.debugUseRoot(root);
      addTearDown(() => IrLibLocalRepo.debugUseRoot(null));

      await expectLater(
        IrLibLocalRepo().download(owner: 'o', repo: 'r', branch: 'b'),
        throwsA(anything),
      );
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(incoming.existsSync(), isFalse);
      expect(markerIn(root), 'old');
    });
  });
}
