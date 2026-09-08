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

  UnpackTally unpack(List<String> names, {void Function(int)? onProgress}) =>
      IrLibLocalRepo.unpackWrappedArchiveTo(
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

  /// The mirror of [blockWithFile]: a directory exactly where an entry's file
  /// must go, so the *write* throws rather than the directory creation before
  /// it. Both halves matter - a reserved name used as a directory component
  /// fails in createSync, the same name used as the file fails in the write,
  /// and only this one reaches the second branch.
  void blockWithDir(String relative) {
    Directory(
      '${root.path}$sep${relative.replaceAll('/', sep)}',
    ).createSync(recursive: true);
  }

  group('unpackWrappedArchiveTo', () {
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
      expect(tally.dropped, 1);
      expect(File('${base.path}${sep}evil.ir').existsSync(), isFalse);
    });

    test('skips an entry sitting beside the wrapper folder', () {
      final tally = unpack(['README.md', '$wrapper/Sony/TV.ir']);

      expect(tally.extracted, 1);
      expect(tally.dropped, 1);
      expect(tally.skipped, 0);
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

    // blockWithFile only ever throws from ensureDir, so without this the write
    // branch is never exercised - and `extracted += 1` could sit above the
    // write that throws with the whole suite still green.
    test('skips an entry whose write itself fails', () {
      blockWithDir('Sony/TV.ir');

      final tally = unpack(['$wrapper/Sony/TV.ir', '$wrapper/Sony/Radio.ir']);

      expect(tally.extracted, 1, reason: 'only Radio.ir can be written');
      expect(tally.skipped, 1);
      expect(tally.firstError, contains('TV.ir'));
      expect(under('Sony/Radio.ir').existsSync(), isTrue);
    });

    test('keeps the first failure rather than the last', () {
      blockWithFile('Alpha');
      blockWithDir('Beta/TV.ir');

      final tally = unpack([
        '$wrapper/Alpha/TV.ir',
        '$wrapper/Beta/TV.ir',
        '$wrapper/Sony/TV.ir',
      ]);

      expect(tally.skipped, 2);
      expect(tally.firstError, contains('Alpha'));
      expect(tally.firstError, isNot(contains('Beta')));
    });

    // The reconciliation that makes a quietly lost entry impossible: a file
    // entry that is neither written nor refused nor declined would break this.
    test('accounts for every file entry exactly once', () {
      blockWithFile('Blocked');

      final names = [
        '$wrapper/Blocked/a.ir',
        '$wrapper/Sony/TV.ir',
        '$wrapper/../../evil.ir',
        'README.md',
        '$wrapper/Empty/',
      ];
      final tally = unpack(names);
      final fileEntries = names.where((n) => !n.endsWith('/')).length;

      expect(tally.extracted + tally.skipped + tally.dropped, fileEntries);
    });

    // ZipDecoder does not throw on an entry whose local header it cannot read -
    // it yields a nameless, empty file. That is a lost file, so it has to be a
    // skip; counting it as dropped would report the loss as normal.
    test('counts an entry the decoder could not name as a skip', () {
      final archive = Archive()
        ..add(ArchiveFile.string('', 'unreadable'))
        ..add(ArchiveFile.string('$wrapper/Sony/TV.ir', 'ok'));

      final tally = IrLibLocalRepo.unpackWrappedArchiveTo(
        archive,
        root.path,
        separator: sep,
      );

      expect(tally.extracted, 1);
      expect(tally.skipped, 1);
      expect(tally.dropped, 0);
      expect(tally.firstError, contains('unnamed'));
    });

    // The catch is deliberately narrow. Folding a decoder bug or an OOM into
    // "the filesystem refused it" would keep the loop running through 15,000
    // more entries and report the result as a partial success.
    test('lets a failure that is not the filesystem refusing it propagate', () {
      // symlink sets neither content field, so readBytes() returns null and
      // the null-check operator throws - the cheapest non-Exception throwable.
      final archive = Archive()
        ..add(ArchiveFile.symlink('$wrapper/link.ir', '../target.ir'));

      expect(
        () => IrLibLocalRepo.unpackWrappedArchiveTo(
          archive,
          root.path,
          separator: sep,
        ),
        throwsA(isA<TypeError>()),
      );
    });

    // The progress call sits outside the try for this reason: inside it, a
    // callback that threw was recorded as the filesystem refusing an entry
    // that had in fact just been written, so one entry counted as both
    // extracted and skipped.
    test(
      'does not record a written entry as refused if the callback throws',
      () {
        // A FileSystemException specifically: a progress callback that touches
        // the disk can raise one, and it is the only class the entry handler
        // would otherwise mistake for the write itself having failed.
        expect(
          () => unpack([
            '$wrapper/Sony/TV.ir',
            '$wrapper/Sony/Radio.ir',
          ], onProgress: (_) => throw const FileSystemException('callback')),
          throwsA(isA<FileSystemException>()),
        );
        expect(under('Sony/TV.ir').existsSync(), isTrue);
      },
    );

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

  group('failureFor', () {
    UnpackTally tally({
      int extracted = 0,
      int skipped = 0,
      int dropped = 0,
      String? firstError = 'x: boom',
    }) => UnpackTally(
      extracted: extracted,
      skipped: skipped,
      dropped: dropped,
      firstError: firstError,
    );

    test('passes a clean unpack', () {
      expect(IrLibLocalRepo.failureFor(tally(extracted: 100), 100), isNull);
    });

    // What the per-entry tolerance exists for: a few pathological names cost
    // the user those entries, not the library.
    test('passes a handful of refused entries', () {
      expect(
        IrLibLocalRepo.failureFor(tally(extracted: 9990, skipped: 10), 10000),
        isNull,
      );
    });

    // The regression the tolerance could otherwise introduce. download() has
    // already deleted the previous library, so a quiet partial result replaces
    // a good library with a worse one and says nothing.
    test('fails when a material share of the library is lost', () {
      final why = IrLibLocalRepo.failureFor(
        tally(extracted: 12000, skipped: 3000),
        15000,
      );

      expect(why, isNotNull);
      expect(why, contains('3000 of 15000'));
      expect(why, contains('boom'));
    });

    test('fails when nothing was written', () {
      expect(
        IrLibLocalRepo.failureFor(tally(skipped: 12), 12),
        contains('all 12 entries failed'),
      );
    });

    // A flat archive with no wrapper folder: nothing failed, nothing resolved.
    // Reporting "all N entries failed, first: null" would be a lie twice over.
    test('names the wrong archive shape rather than blaming failures', () {
      final why = IrLibLocalRepo.failureFor(
        tally(dropped: 4, firstError: null),
        4,
      );

      expect(why, contains('none of 4 entries resolved'));
      expect(why, isNot(contains('null')));
    });

    test('names an empty archive', () {
      expect(
        IrLibLocalRepo.failureFor(tally(firstError: null), 0),
        contains('no files'),
      );
    });
  });
}
