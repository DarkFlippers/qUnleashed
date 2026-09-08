import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/infrared/local_repo.dart';

/// The IRDB zip wraps its whole tree in one top-level folder, which
/// `resolveWrappedArchivePath` strips, so every entry name here carries it.
const String wrapper = 'Flipper-IRDB-main';

final String sep = Platform.pathSeparator;

Archive archiveOf(List<String> names) {
  final archive = Archive();
  for (final name in names) {
    archive.add(
      name.endsWith('/')
          ? ArchiveFile.directory(name)
          : ArchiveFile.string(name, 'content of $name'),
    );
  }
  return archive;
}

void main() {
  /// [root] sits inside [base] so an entry that escapes the root still lands
  /// in a directory the test owns and can assert on.
  late Directory base;
  late Directory root;

  setUp(() {
    base = Directory.systemTemp.createTempSync('ir_unpack_test');
    root = Directory('${base.path}${sep}library')..createSync();
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  ({int extracted, int skipped, String? firstError}) unpack(
    List<String> names, {
    void Function(int)? onProgress,
  }) => IrLibLocalRepo.unpackArchiveTo(
    archiveOf(names),
    root.path,
    separator: sep,
    onProgress: onProgress,
  );

  File under(String relative) =>
      File('${root.path}$sep${relative.replaceAll('/', sep)}');

  /// Puts a plain file exactly where an entry needs a directory. Creating that
  /// directory then fails on every platform, which is the point: this is the
  /// class of failure no name check can predict, standing in for a reserved
  /// device name on Windows or a full disk anywhere.
  void blockWithFile(String name) {
    File('${root.path}$sep$name').writeAsStringSync('in the way');
  }

  group('unpackArchiveTo', () {
    test('writes every entry under the root', () {
      final tally = unpack(['$wrapper/Samsung/TV.ir', '$wrapper/Sony/TV.ir']);

      expect(tally.extracted, 2);
      expect(tally.skipped, 0);
      expect(tally.firstError, isNull);
      expect(under('Samsung/TV.ir').readAsStringSync(), contains('Samsung'));
      expect(under('Sony/TV.ir').existsSync(), isTrue);
    });

    // The regression this guards is the whole point of the change: the loop
    // had no per-entry handler, and the isolate ran with errorsAreFatal, so a
    // single unwritable entry failed the import of all ~15,000.
    test('skips an entry the filesystem refuses and keeps the rest', () {
      blockWithFile('Blocked');

      final tally = unpack([
        '$wrapper/Blocked/TV.ir',
        '$wrapper/Sony/TV.ir',
        '$wrapper/Samsung/TV.ir',
      ]);

      expect(tally.extracted, 2);
      expect(tally.skipped, 1);
      expect(tally.firstError, contains('Blocked'));
      expect(under('Sony/TV.ir').existsSync(), isTrue);
      expect(under('Samsung/TV.ir').existsSync(), isTrue);
    });

    test('keeps writing after a failure that appears first', () {
      blockWithFile('Blocked');

      final tally = unpack([
        '$wrapper/Blocked/a.ir',
        '$wrapper/Blocked/b.ir',
        '$wrapper/Sony/TV.ir',
      ]);

      expect(tally.skipped, 2);
      expect(tally.extracted, 1);
      expect(under('Sony/TV.ir').existsSync(), isTrue);
    });

    // Nothing extracted is not a partial success, and the caller turns this
    // tally into the error that used to be raised for any failure at all.
    test('reports nothing extracted when every entry fails', () {
      blockWithFile('Blocked');

      final tally = unpack(['$wrapper/Blocked/a.ir', '$wrapper/Blocked/b.ir']);

      expect(tally.extracted, 0);
      expect(tally.skipped, 2);
      expect(tally.firstError, isNotNull);
    });

    test('reports nothing extracted for an archive with no entries', () {
      expect(unpack([]).extracted, 0);
    });

    // A refused name is the containment check working, not the filesystem
    // failing, so it must not inflate the skip count the caller logs.
    test('refuses a traversal without counting it as a failure', () {
      final tally = unpack(['$wrapper/../../evil.ir', '$wrapper/Sony/TV.ir']);

      expect(tally.extracted, 1);
      expect(tally.skipped, 0);
      expect(File('${base.path}${sep}evil.ir').existsSync(), isFalse);
      expect(File('${base.parent.path}${sep}evil.ir').existsSync(), isFalse);
    });

    test('skips an entry sitting beside the wrapper folder', () {
      expect(unpack(['README.md', '$wrapper/Sony/TV.ir']).extracted, 1);
    });

    // The directory cache records only successful creations, so every file
    // after the first in a folder still has to land.
    test('writes every file in a folder the first entry created', () {
      final names = [for (var i = 0; i < 5; i++) '$wrapper/Samsung/TV$i.ir'];

      expect(unpack(names).extracted, 5);
      for (var i = 0; i < 5; i++) {
        expect(under('Samsung/TV$i.ir').existsSync(), isTrue);
      }
    });

    // The cache records a directory only once createSync actually succeeded,
    // so a failure that later clears - a lock released, space freed - is
    // retried instead of being remembered as done. onProgress is the only hook
    // that runs mid-loop, so it is what clears the obstruction here.
    test('retries a directory whose creation failed earlier', () {
      blockWithFile('Blocked');

      final tally = unpack(
        [
          '$wrapper/Blocked/a.ir',
          '$wrapper/Sony/TV.ir',
          '$wrapper/Blocked/b.ir',
        ],
        onProgress: (_) {
          final blocking = File('${root.path}${sep}Blocked');
          if (blocking.existsSync()) blocking.deleteSync();
        },
      );

      expect(tally.skipped, 1, reason: 'only the entry before the fix clears');
      expect(tally.extracted, 2);
      expect(under('Blocked/b.ir').existsSync(), isTrue);
    });

    test('creates a directory entry that carries no file', () {
      final tally = unpack(['$wrapper/Empty/', '$wrapper/Sony/TV.ir']);

      expect(
        tally.extracted,
        1,
        reason: 'a directory is not an extracted file',
      );
      expect(tally.skipped, 0);
      expect(Directory('${root.path}${sep}Empty').existsSync(), isTrue);
    });

    test('reports progress once per written file', () {
      final seen = <int>[];

      unpack([
        '$wrapper/a.ir',
        '$wrapper/Empty/',
        '$wrapper/b.ir',
        '$wrapper/c.ir',
      ], onProgress: seen.add);

      expect(seen, [1, 2, 3]);
    });
  });
}
