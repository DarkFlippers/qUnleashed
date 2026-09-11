import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive_unpack.dart';
import 'package:qunleashed/pages/apps/data/atp/atp_source.dart';

/// A pack zip wraps its apps in a per-build folder whose name starts with
/// `artifacts-`; everything before and including it is stripped.
const String wrapper = 'artifacts-0.0.1';

final String sep = Platform.pathSeparator;

Archive archiveOf(Map<String, String?> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    if (name.endsWith('/')) {
      archive.add(ArchiveFile.directory(name));
    } else if (content == null) {
      // What the decoder yields for an entry whose content it cannot read:
      // named, marked a file, and empty. readBytes() returns null for it.
      archive.add(ArchiveFile.noData(name));
    } else {
      archive.add(ArchiveFile.string(name, content));
    }
  });
  return archive;
}

void main() {
  late Directory base;
  late Directory root;

  setUp(() {
    base = Directory.systemTemp.createTempSync('atp_unpack_test');
    // root sits inside base so an entry that escapes it still lands somewhere
    // the test owns and can assert on.
    root = Directory('${base.path}${sep}pack')..createSync();
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  Future<UnpackTally> unpack(Map<String, String?> entries) =>
      AtpArchive.unpackPackTo(archiveOf(entries), root.path, separator: sep);

  String read(String relative) => File(
    '${root.path}$sep${relative.replaceAll('/', sep)}',
  ).readAsStringSync();

  bool exists(String relative) =>
      File('${root.path}$sep${relative.replaceAll('/', sep)}').existsSync();

  group('unpacking a pack', () {
    test('writes the apps and strips the artifacts wrapper', () async {
      final tally = await unpack({
        '$wrapper/hello.fap': 'hello bytes',
        '$wrapper/games/snake.fap': 'snake bytes',
      });

      expect(tally.extracted, 2);
      expect(read('hello.fap'), 'hello bytes');
      expect(read('games/snake.fap'), 'snake bytes');
    });

    test('ignores everything that is not a .fap', () async {
      final tally = await unpack({
        '$wrapper/hello.fap': 'hello bytes',
        '$wrapper/manifest.txt': 'not an app',
        '$wrapper/build.log': 'noise',
        '$wrapper/logs/': null,
      });

      // Ignored, not dropped: the pack carries these on purpose, and counting
      // them as losses would make a healthy pack look damaged.
      expect(tally.extracted, 1);
      expect(tally.skipped, 0);
      expect(tally.dropped, 0);
      expect(exists('manifest.txt'), isFalse);
    });

    test('takes an entry that has no wrapper at all', () async {
      final tally = await unpack({'hello.fap': 'hello bytes'});

      expect(tally.extracted, 1);
      expect(read('hello.fap'), 'hello bytes');
    });

    test('strips everything up to and including the wrapper', () async {
      await unpack({'some/where/$wrapper/deep/hello.fap': 'hello bytes'});

      expect(read('deep/hello.fap'), 'hello bytes');
    });
  });

  group('entries that cannot be written', () {
    // The defect this fixes: one bad entry used to abort the whole pack, so
    // the user got none of the apps rather than all but one.
    test('a traversal is dropped and the rest still land', () async {
      final tally = await unpack({
        '$wrapper/../escaped.fap': 'nope',
        '$wrapper/hello.fap': 'hello bytes',
      });

      expect(tally.extracted, 1);
      expect(tally.dropped, 1);
      expect(read('hello.fap'), 'hello bytes');
      expect(File('${base.path}${sep}escaped.fap').existsSync(), isFalse);
    });

    // The second defect: `readBytes() ?? const []` wrote a 0-byte .fap and
    // counted it installed. fetchFap then found a file, so the installer got
    // an empty app instead of being told the app was not in the pack.
    test('an unreadable entry is skipped, not written empty', () async {
      final tally = await unpack({
        '$wrapper/broken.fap': null,
        '$wrapper/hello.fap': 'hello bytes',
      });

      expect(tally.extracted, 1);
      expect(tally.skipped, 1);
      expect(exists('broken.fap'), isFalse);
      expect(tally.firstError, contains('broken.fap'));
    });

    // The filesystem refusing one entry is what #22 was filed for on the IR
    // side, and what aborted the whole pack here. A directory sitting where
    // the .fap must go is the cheapest way to make a real FileSystemException
    // rather than a simulated one.
    test(
      'a write the filesystem refuses is skipped, the rest still land',
      () async {
        Directory('${root.path}${sep}blocked.fap').createSync(recursive: true);

        final tally = await unpack({
          '$wrapper/blocked.fap': 'cannot land',
          '$wrapper/hello.fap': 'hello bytes',
        });

        expect(tally.extracted, 1);
        expect(tally.skipped, 1);
        expect(tally.firstError, contains('blocked.fap'));
        expect(read('hello.fap'), 'hello bytes');
      },
    );

    test('a parent directory that cannot be made is skipped', () async {
      // A file where the entry's folder needs to be: creating the directory
      // fails, which must cost that entry and nothing else.
      File('${root.path}${sep}games').writeAsStringSync('in the way');

      final tally = await unpack({
        '$wrapper/games/snake.fap': 'snake bytes',
        '$wrapper/hello.fap': 'hello bytes',
      });

      expect(tally.extracted, 1);
      expect(tally.skipped, 1);
      expect(read('hello.fap'), 'hello bytes');
    });

    test('the first failure is the one reported', () async {
      final tally = await unpack({
        '$wrapper/first.fap': null,
        '$wrapper/second.fap': null,
      });

      expect(tally.skipped, 2);
      expect(tally.firstError, contains('first.fap'));
      expect(tally.firstError, isNot(contains('second.fap')));
    });

    test('every .fap entry is counted exactly once', () async {
      final tally = await unpack({
        '$wrapper/good.fap': 'bytes',
        '$wrapper/broken.fap': null,
        '$wrapper/../escaped.fap': 'nope',
        '$wrapper/notes.txt': 'ignored',
      });

      expect(tally.extracted + tally.skipped + tally.dropped, 3);
    });
  });

  group('deciding whether the pack is usable', () {
    UnpackTally tally({
      int extracted = 0,
      int skipped = 0,
      int dropped = 0,
      String? firstError,
    }) => UnpackTally(
      extracted: extracted,
      skipped: skipped,
      dropped: dropped,
      firstError: firstError,
    );

    test('one app written is enough, whatever else was lost', () {
      // Laxer than the IR library on purpose: a missing app is reported by
      // name when someone tries to install it, so a partial pack is worth
      // more to the user than no pack at all.
      expect(AtpArchive.failureFor(tally(extracted: 1, skipped: 99)), isNull);
    });

    test('a pack carrying no apps fails', () {
      expect(AtpArchive.failureFor(tally()), contains('no .fap entries'));
    });

    test('a pack whose entries all escaped fails', () {
      expect(
        AtpArchive.failureFor(tally(dropped: 3)),
        contains('outside the pack directory'),
      );
    });

    test('a pack nothing could be written from fails, with the reason', () {
      expect(
        AtpArchive.failureFor(
          tally(skipped: 2, dropped: 1, firstError: 'a.fap: disk full'),
        ),
        allOf(contains('all 3 entries failed'), contains('disk full')),
      );
    });
  });
}
