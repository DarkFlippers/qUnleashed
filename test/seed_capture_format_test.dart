// The parser for the files the Flipper-side `seed_capturer` app writes.
//
// The sample below is the format that app actually emits - the field order and
// spelling are taken from its `seed_save()`, not invented here.
//
// What it cannot see: whether the capture app still writes this. The two are
// separate repositories, so the only thing that notices a format change is a
// user whose capture stops parsing - which is why the parser names what it
// skipped rather than failing silently.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_capture_format.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

const _capture = '''
Filetype: Flipper SubGhz Seed Capture
Version: 1
# Fix + Hop set for offline seed recovery, not a playable .sub
Received: 2026-10-06 21:14:33
Manufacturer: Genius
Protocol: Faac SLH
Frequency: 868350000
Preset: FuriHalSubGhzPresetOok650Async
Fix: A0DC9330
Hops: 3
# Hops in the order they were received
Hop: 29389EF7
Hop: 40101499
Hop: A1F9C88F
''';

void main() {
  group('a capture the app wrote', () {
    test('parses every field', () {
      final parsed = SeedCaptureFormat.parse(_capture, path: '/ext/x.txt');
      expect(parsed.skipped, isEmpty);

      final capture = parsed.capture!;
      expect(capture.fix, 0xA0DC9330);
      expect(capture.hops, [0x29389EF7, 0x40101499, 0xA1F9C88F]);
      expect(capture.manufacturer, SeedManufacturer.genius);
      expect(capture.frequencyHz, 868350000);
      expect(capture.isSolvable, isTrue);
    });

    test('keeps the hops in the order they were received', () {
      // Not presentation: the engine accepts a seed only if consecutive hops
      // decrypt to consecutive counters, so a reordered list does not solve.
      final capture = SeedCaptureFormat.parse(_capture).capture!;
      expect(capture.hops.first, 0x29389EF7);
      expect(capture.hops.last, 0xA1F9C88F);
    });

    test('survives CRLF, which is how the file arrives off some cards', () {
      final capture = SeedCaptureFormat.parse(_capture.replaceAll('\n', '\r\n'))
          .capture;
      expect(capture, isNotNull);
      expect(capture!.hops, hasLength(3));
    });
  });

  group('what it tolerates', () {
    test('skips an unreadable hop and names it, keeping the rest', () {
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Hop: 40101499', 'Hop: ZZZZ'),
      );
      expect(parsed.capture!.hops, [0x29389EF7, 0xA1F9C88F]);
      expect(parsed.skipped, contains(contains('ZZZZ')));
    });

    test('says so when the declared count and the hops disagree', () {
      // A truncated write. Worth reporting because the hops that survived may
      // no longer be consecutive, and the search would then find nothing for a
      // reason that is not about the remote.
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Hops: 3', 'Hops: 9'),
      );
      expect(parsed.capture, isNotNull);
      expect(parsed.skipped, contains(contains('says 9 hops, found 3')));
    });

    test('ignores comments, blank lines and unknown fields', () {
      final parsed = SeedCaptureFormat.parse(
        '$_capture\n\n# a comment\nSomethingNew: 42\n',
      );
      expect(parsed.capture, isNotNull);
      expect(parsed.skipped, isEmpty);
    });

    test('works without the optional fields', () {
      final parsed = SeedCaptureFormat.parse('''
Manufacturer: Erreka
Fix: 20345678
Hop: BA072EA1
Hop: 6BD12D54
''');
      final capture = parsed.capture!;
      expect(capture.manufacturer, SeedManufacturer.erreka);
      expect(capture.frequencyHz, isNull);
    });

    test('accepts a manufacturer however it is spaced or cased', () {
      for (final spelling in ['FAAC SLH', 'faac_slh', 'FaacSlh']) {
        expect(
          SeedCaptureFormat.parse('''
Manufacturer: $spelling
Fix: 12345674
Hop: D6661744
Hop: 674875BE
''').capture?.manufacturer,
          SeedManufacturer.faacSlh,
          reason: '"$spelling" should resolve',
        );
      }
    });
  });

  group('a capture longer than the engine takes', () {
    test("is kept whole; the limit is the search's, not the file's", () {
      // More presses is a *better* capture. Trimming here would throw away
      // hops a shorter window could have used to step over a gap, so the
      // engine's limit is applied where the windows are built instead - the
      // parser's job is to say what the file contains.
      final hops = [
        for (var i = 0; i < SeedCapture.maxHops + 3; i++)
          'Hop: ${(0x10000000 + i).toRadixString(16).toUpperCase()}',
      ].join('\n');
      final parsed = SeedCaptureFormat.parse('''
Manufacturer: Genius
Fix: A0DC9330
$hops
''');
      expect(parsed.capture!.hops, hasLength(SeedCapture.maxHops + 3));
      expect(parsed.skipped, isEmpty);
    });
  });

  group('what it refuses', () {
    test('a file with no fixed code', () {
      final parsed = SeedCaptureFormat.parse('Hop: 29389EF7\nHop: 40101499\n');
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('Fix')));
    });

    test('a manufacturer this build has no key for', () {
      // Named rather than guessed: picking a mode would not fail, it would
      // sweep the whole space and report that no seed exists - the one answer
      // a user must not be given wrongly.
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Manufacturer: Genius', 'Manufacturer: Nice'),
      );
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('Nice')));
    });

    test('a single hop, which cannot be checked against anything', () {
      final parsed = SeedCaptureFormat.parse('''
Manufacturer: Genius
Fix: A0DC9330
Hop: 29389EF7
''');
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('at least 2')));
    });

    test('some other Flipper file that happens to be here', () {
      final parsed = SeedCaptureFormat.parse('''
Filetype: Flipper SubGhz Key File
Version: 1
Protocol: Faac SLH
''');
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('not a seed capture')));
    });

    test('two different fixed codes in one file', () {
      // Two remotes in range, or a file appended to. Keeping the first and
      // merging both sets of hops produces a capture whose hops are not all
      // from one remote, which sweeps the whole space and ends on "nothing
      // matched" - the one answer this feature must not give wrongly.
      //
      // This assertion used to be only the `skipped` one, in a group called
      // "what it refuses", against code that did not refuse.
      final parsed = SeedCaptureFormat.parse('$_capture\nFix: 11111111\n');
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('given twice')));
    });

    test('a frequency that is not one', () {
      // int.tryParse alone takes `0` and `-1`, and a .sub written with either
      // transmits into the void - which is the whole reason the field is held
      // as nullable rather than defaulted.
      for (final bad in ['0', '-1', '12', 'nonsense', '']) {
        final parsed = SeedCaptureFormat.parse(
          _capture.replaceFirst('Frequency: 868350000', 'Frequency: $bad'),
        );
        expect(
          parsed.capture?.frequencyHz,
          isNull,
          reason: '"$bad" is not a frequency',
        );
      }
    });
  });
}
