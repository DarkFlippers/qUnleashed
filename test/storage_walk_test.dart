import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/storage/paths.dart';

import 'kept_lines.dart';

/// The two walks behind Settings → Storage.
///
/// One reports a size and the other clears a folder, and both used to pass
/// over what they could not do in silence. A size short by a locked folder is
/// a wrong number presented as a fact; a clear that leaves files behind
/// reports success over a folder that still has things in it.
///
/// Nothing is waiting on either - the screen has its number, the button has
/// returned - so the answer is a kept log rather than a surface. ADR 0008.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('storage_walk_test');
    clearKeptLines();
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  bool said(String fragment) => keptLines.any((l) => l.contains(fragment));

  File write(String name, int bytes) {
    final file = File('${root.path}${Platform.pathSeparator}$name')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(bytes, 0));
    return file;
  }

  group('measuring a folder', () {
    test('adds up every file in it', () async {
      write('a.bin', 10);
      write('b.bin', 15);
      write('nested${Platform.pathSeparator}c.bin', 5);

      expect(await directorySize(root), 30);
    });

    test('says nothing when it could measure everything', () async {
      write('a.bin', 10);

      await directorySize(root);

      expect(said('[Storage]'), isFalse);
    });

    test('is zero for a folder that is not there', () async {
      final missing = Directory('${root.path}${Platform.pathSeparator}gone');

      expect(await directorySize(missing), 0);
      expect(said('[Storage]'), isFalse);
    });

    test('is zero for an empty one, and says nothing', () async {
      expect(await directorySize(root), 0);
      expect(said('[Storage]'), isFalse);
    });
  });

  group('clearing a folder', () {
    test('removes what is in it', () async {
      write('a.bin', 10);
      write('nested${Platform.pathSeparator}c.bin', 5);

      await clearDirectory(root);

      expect(root.listSync(), isEmpty);
    });

    test('says nothing when it cleared everything', () async {
      write('a.bin', 10);

      await clearDirectory(root);

      expect(said('[Storage]'), isFalse);
    });

    test('does nothing, quietly, for a folder that is not there', () async {
      final missing = Directory('${root.path}${Platform.pathSeparator}gone');

      await expectLater(clearDirectory(missing), completes);
      expect(said('[Storage]'), isFalse);
    });

    // The failure worth having a line for: a file held open elsewhere. It is
    // reported per call rather than per entry, because a locked folder fails
    // every file in it at once.
    test('says how many entries it had to leave', () async {
      write('a.bin', 10);
      final held = write('locked.bin', 10);
      final handle = held.openSync(mode: FileMode.append);
      addTearDown(handle.closeSync);

      await clearDirectory(root);

      if (root.listSync().isEmpty) {
        // POSIX lets an open file be unlinked, so there is nothing to report
        // and nothing to assert beyond that it stayed quiet.
        expect(said('could not remove'), isFalse);
        return;
      }
      expect(said('could not remove 1 entr'), isTrue);
    });
  });
}
