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

/// The two lines every capture has to carry, for fixtures that are about
/// something else.
const _header = 'Filetype: Flipper SubGhz Seed Capture\nVersion: 1\n';

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
      final parsed = SeedCaptureFormat.parse(_capture);
      expect(parsed.skipped, isEmpty);

      final capture = parsed.capture!;
      expect(capture.fix, 0xA0DC9330);
      expect(capture.hops, [0x29389EF7, 0x40101499, 0xA1F9C88F]);
      expect(capture.manufacturer, SeedManufacturer.genius);
      expect(capture.frequencyHz, 868350000);
      expect(capture.isSolvable, isTrue);
    });

    test('keeps the hops in the order they were received', () {
      // Not presentation: the engine accepts only counters running in one
      // direction, so a shuffled list does not solve and an exact reversal
      // solves with the wrong counter. See `SeedCapture.hops`; the native probe
      // pins both.
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

    test('drops a hop that repeats the one before it', () {
      // The engine refuses a step of zero, so a capture keeping the repeat
      // cannot solve as a whole - and no contiguous window excludes an
      // interior duplicate, so the retry ladder cannot rescue it either. The
      // user would sweep the whole space three times to be told nothing
      // matched.
      final parsed = SeedCaptureFormat.parse(
        _capture
            .replaceFirst('Hops: 3', 'Hops: 4')
            .replaceFirst('Hop: 40101499', 'Hop: 40101499\nHop: 40101499'),
      );
      expect(parsed.capture!.hops, [0x29389EF7, 0x40101499, 0xA1F9C88F]);
      expect(parsed.skipped, [contains('repeated hop: "40101499"')]);
    });

    test('a repeated hop is not also reported as a truncated write', () {
      // Two different faults with two different pieces of advice. The declared
      // count is checked against the hop lines that parsed, so dropping a
      // duplicate does not make the file look cut short.
      final parsed = SeedCaptureFormat.parse(
        _capture
            .replaceFirst('Hops: 3', 'Hops: 4')
            .replaceFirst('Hop: 40101499', 'Hop: 40101499\nHop: 40101499'),
      );
      expect(parsed.skipped, isNot(contains(contains('file says'))));
    });

    test('keeps a hop that repeats one further back', () {
      // Not a repeated write but a direction break: counters that go up and
      // come back down. The engine has to see it and refuse - the probe pins
      // that case - so the parser must not quietly make the capture look
      // solvable.
      final parsed = SeedCaptureFormat.parse(
        _capture
            .replaceFirst('Hops: 3', 'Hops: 4')
            .replaceFirst('Hop: A1F9C88F', 'Hop: A1F9C88F\nHop: 29389EF7'),
      );
      expect(parsed.capture!.hops, [
        0x29389EF7,
        0x40101499,
        0xA1F9C88F,
        0x29389EF7,
      ]);
      expect(parsed.skipped, isEmpty);
    });

    test('says so when the declared count and the hops disagree', () {
      // A truncated write. Worth reporting because the hops that survived can
      // be left with a gap wider than the engine tolerates, and the search
      // would then find nothing for a reason that is not about the remote.
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
Filetype: Flipper SubGhz Seed Capture
Version: 1
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
        final parsed = SeedCaptureFormat.parse('''
Filetype: Flipper SubGhz Seed Capture
Version: 1
Manufacturer: $spelling
Fix: 12345674
Hop: D6661744
Hop: 674875BE
''');
        expect(parsed.capture, isNotNull, reason: '"$spelling" should resolve');
        expect(parsed.capture!.manufacturer, SeedManufacturer.faacSlh);
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
Filetype: Flipper SubGhz Seed Capture
Version: 1
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
      final parsed = SeedCaptureFormat.parse(
        '${_header}Hop: 29389EF7\nHop: 40101499\n',
      );
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
Filetype: Flipper SubGhz Seed Capture
Version: 1
Manufacturer: Genius
Fix: A0DC9330
Hop: 29389EF7
''');
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('at least 2')));
    });

    test('a file with no Filetype header at all', () {
      // Checked only when present before, so a headerless file was accepted
      // and attacked.
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Filetype: Flipper SubGhz Seed Capture\n', ''),
      );
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('not a seed capture')));
    });

    test('a version this build does not read', () {
      // The capture app's own statement that the layout moved. Ignoring it is
      // how a v2 file parses cleanly under v1 rules and comes back "no seed
      // matched", sending the user to re-record a remote that was fine.
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Version: 1', 'Version: 2'),
      );
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('version 2')));
    });

    test('a protocol that disagrees with the manufacturer', () {
      // The file says both, and this build knows the pairing - a disagreement
      // is the strongest signal available that the format changed.
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Protocol: Faac SLH', 'Protocol: KeeLoq'),
      );
      expect(parsed.capture, isNull);
      expect(parsed.skipped, contains(contains('Protocol')));
    });

    test('a truncated hex word, which is not a short number', () {
      // `Hop: 2938` would parse as 0x00002938, join the capture and poison it,
      // and the declared-count check cannot see it because the line is there.
      final parsed = SeedCaptureFormat.parse(
        _capture.replaceFirst('Hop: 40101499', 'Hop: 4010'),
      );
      expect(parsed.capture!.hops, [0x29389EF7, 0xA1F9C88F]);
      expect(parsed.skipped, contains(contains('4010')));
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
        // Both halves, and not through `?.`: with the null-aware operator this
        // passed whenever the whole file was refused, which is a different
        // behaviour under the same assertion - and this group is called "what
        // it refuses", so it would have read as covering it.
        expect(
          parsed.capture,
          isNotNull,
          reason: '"$bad" should not refuse the file',
        );
        expect(
          parsed.capture!.frequencyHz,
          isNull,
          reason: '"$bad" is not a frequency',
        );
      }
    });
  });
}
