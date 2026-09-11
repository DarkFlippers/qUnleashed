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

  /// The delete of the superseded tree is deliberately not awaited, so give it
  /// a turn before asserting it is gone.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  group('swapping a new library in', () {
    test('the new tree replaces the old one', () async {
      treeAt(root, 'old');
      treeAt(incoming, 'new');

      await IrLibLocalRepo.swapIn(root, incoming);
      await settle();

      expect(markerIn(root), 'new');
      expect(incoming.existsSync(), isFalse);
      expect(superseded.existsSync(), isFalse, reason: 'cleared afterwards');
    });

    test('works when there was no library to replace', () async {
      treeAt(incoming, 'new');

      await IrLibLocalRepo.swapIn(root, incoming);
      await settle();

      expect(markerIn(root), 'new');
    });

    test('a leftover superseded tree does not block the swap', () async {
      treeAt(root, 'old');
      treeAt(incoming, 'new');
      treeAt(superseded, 'older still');

      await IrLibLocalRepo.swapIn(root, incoming);
      await settle();

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
}
