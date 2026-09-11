import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive_unpack.dart';
import 'package:qunleashed/pages/apps/data/atp/atp_source.dart';

/// A pack zip wraps its apps in a per-build folder whose name starts with
/// `artifacts-`; everything up to and including it is stripped.
const String wrapper = 'artifacts-0.0.1';

final String sep = Platform.pathSeparator;

/// Content large enough that the encoder deflates it rather than storing it,
/// so corrupting the payload actually breaks an inflate.
final String compressible = List.filled(
  400,
  'the quick brown fox jumps over it. ',
).join();

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

  /// Builds a real zip and reads it back through ZipDecoder, which is the only
  /// way to get the entry shapes production sees. Hand-built `Archive` objects
  /// can express entries the decoder never produces - `ArchiveFile.noData`
  /// gives a null `readBytes()`, while a decoded zero-length entry gives an
  /// empty list - and a test built on one of those proves nothing about the
  /// code that has to cope with the other.
  Archive decodedZip(
    Map<String, String> entries, {
    String? corruptPayloadOf,
    String? breakHeaderOf,
  }) {
    final source = Archive();
    entries.forEach((name, content) {
      source.add(
        name.endsWith('/')
            ? ArchiveFile.directory(name)
            : ArchiveFile.bytes(name, Uint8List.fromList(utf8.encode(content))),
      );
    });
    final bytes = Uint8List.fromList(ZipEncoder().encode(source));

    /// Where an entry's name starts in its local header.
    int nameAt(String name) {
      final marker = utf8.encode(name);
      for (var i = 0; i + marker.length < bytes.length; i++) {
        var hit = true;
        for (var j = 0; j < marker.length; j++) {
          if (bytes[i + j] != marker[j]) {
            hit = false;
            break;
          }
        }
        if (hit) return i;
      }
      fail('entry "$name" not found in the encoded zip');
    }

    if (corruptPayloadOf != null) {
      // The payload follows the name, so writing well past the name lands
      // inside the deflate stream and leaves the name and every other entry's
      // header intact - exactly one entry goes bad, and it goes bad on read.
      final at = nameAt(corruptPayloadOf) + corruptPayloadOf.length;
      for (var i = at + 40; i < at + 80 && i < bytes.length; i++) {
        bytes[i] = 0x00;
      }
    }

    if (breakHeaderOf != null) {
      // A local file header is 30 fixed bytes and then the name, so the
      // signature sits 30 bytes back. Break it and the decoder cannot read the
      // header at all: it still lists the entry from the central directory,
      // but with no name - which is the shape that used to slip past the .fap
      // filter and be counted nowhere.
      final signature = nameAt(breakHeaderOf) - 30;
      expect(signature, greaterThanOrEqualTo(0));
      for (var i = signature; i < signature + 4; i++) {
        bytes[i] = 0x00;
      }
    }

    final path = '${base.path}${sep}source.zip';
    File(path).writeAsBytesSync(bytes);
    final input = InputFileStream(path);
    final archive = ZipDecoder().decodeStream(input);
    addTearDown(input.close);
    return archive;
  }

  Future<UnpackTally> unpack(
    Map<String, String> entries, {
    String? corruptPayloadOf,
    String? breakHeaderOf,
  }) => AtpArchive.unpackPackTo(
    decodedZip(
      entries,
      corruptPayloadOf: corruptPayloadOf,
      breakHeaderOf: breakHeaderOf,
    ),
    root.path,
    separator: sep,
  );

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
    // The defect: one bad entry used to abort the whole pack, so the user got
    // none of the apps rather than all but one.
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

    // The likeliest way a single entry goes bad, and the one a
    // FileSystemException-only handler misses: readBytes throws
    // FormatException on a stream it cannot inflate.
    test('a corrupt payload is skipped and the rest still land', () async {
      final tally = await unpack({
        '$wrapper/rotten.fap': compressible,
        '$wrapper/hello.fap': 'hello bytes',
      }, corruptPayloadOf: '$wrapper/rotten.fap');

      expect(tally.extracted, 1);
      expect(tally.skipped, 1);
      expect(tally.firstError, contains('rotten.fap'));
      expect(exists('rotten.fap'), isFalse);
      expect(read('hello.fap'), 'hello bytes');
    });

    // The second defect: `readBytes() ?? const []` wrote a 0-byte .fap and
    // counted it installed. A decoded zero-length entry yields an empty list
    // rather than null, so emptiness is what has to be checked - and a .fap
    // is a compiled binary that is never legitimately empty.
    test('an entry with no content is skipped, not written empty', () async {
      final tally = await unpack({
        '$wrapper/empty.fap': '',
        '$wrapper/hello.fap': 'hello bytes',
      });

      expect(tally.extracted, 1);
      expect(tally.skipped, 1);
      expect(exists('empty.fap'), isFalse);
      expect(tally.firstError, contains('empty.fap'));
    });

    // A directory sitting where the .fap must go is the cheapest way to make
    // a real FileSystemException rather than a simulated one.
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

    // An entry whose local header cannot be read comes back with no name at
    // all. The name is the only thing that says whether it was an app, so it
    // has to be counted rather than quietly skipped by the .fap filter - a
    // pack of 40 good apps and 5 of these would otherwise report 40 unpacked
    // and no sign that anything was lost.
    test(
      'an entry with an unreadable header is counted, not ignored',
      () async {
        final tally = await unpack({
          '$wrapper/headerless.fap': compressible,
          '$wrapper/hello.fap': 'hello bytes',
        }, breakHeaderOf: '$wrapper/headerless.fap');

        expect(tally.skipped, 1);
        expect(tally.firstError, contains('unnamed'));
        expect(read('hello.fap'), 'hello bytes');
      },
    );

    test('the first failure is the one reported', () async {
      final tally = await unpack({
        '$wrapper/aaa.fap': '',
        '$wrapper/zzz.fap': '',
      });

      expect(tally.skipped, 2);
      expect(tally.firstError, contains('aaa.fap'));
      expect(tally.firstError, isNot(contains('zzz.fap')));
    });

    test('every .fap entry is counted exactly once', () async {
      final tally = await unpack({
        '$wrapper/good.fap': 'bytes',
        '$wrapper/empty.fap': '',
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
