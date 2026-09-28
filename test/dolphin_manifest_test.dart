import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/paint/dolphin/manifest.dart';

/// The manifest the Flipper reads to decide which animation to play.
///
/// It is a file the user can edit by hand in the app, and the firmware parses
/// it on the device — so a block this parser drops is an animation that stops
/// appearing, and a value it mangles is one that plays at the wrong time.
/// Both halves are pure functions over text and neither had a test.
///
/// The shape is a two-line header, then blank-line-separated blocks keyed by
/// `Name:`. Everything else in a block is optional and falls back to what
/// FlipperAnimationManager uses.
ManifestEntry entry(
  String name, {
  int weight = ManifestEntry.kDefaultWeight,
  int minLevel = ManifestEntry.kDefaultMinLevel,
  int maxLevel = ManifestEntry.kDefaultMaxLevel,
}) => ManifestEntry(
  name: name,
  weight: weight,
  minLevel: minLevel,
  maxLevel: maxLevel,
);

/// The entries half of a parse, for the cases that are only about those.
Map<String, ManifestEntry> entriesOf(String text) =>
    DolphinManifest.parse(text).entries;

void main() {
  group('what comes back out', () {
    // The user edits the text and the app reads it back. Anything that does
    // not survive the round trip is a setting they will find changed.
    test('is what went in', () {
      final written = DolphinManifest.build([
        entry('L1_Waves_128x50', weight: 3, minLevel: 2, maxLevel: 7),
        entry('L2_Hex_128x64'),
      ]);

      final read = entriesOf(written);

      expect(read.keys, ['L1_Waves_128x50', 'L2_Hex_128x64']);
      final waves = read['L1_Waves_128x50']!;
      expect(waves.weight, 3);
      expect(waves.minLevel, 2);
      expect(waves.maxLevel, 7);
    });

    test('keeps the defaults it was not told to change', () {
      final read = entriesOf(DolphinManifest.build([entry('A')]));

      final a = read['A']!;
      expect(a.minButthurt, ManifestEntry.kDefaultMinButthurt);
      expect(a.maxButthurt, ManifestEntry.kDefaultMaxButthurt);
      expect(a.weight, ManifestEntry.kDefaultWeight);
    });

    // Everything in the file is there because someone chose it, so a parsed
    // entry is a selected one - the screen ticks them from this.
    test('is selected, because being in the file is the choosing', () {
      final read = entriesOf(DolphinManifest.build([entry('A')]));

      expect(read['A']!.selected, isTrue);
    });
  });

  group('what is written', () {
    test('opens with the header the firmware looks for', () {
      expect(DolphinManifest.build([]), DolphinManifest.header);
      expect(DolphinManifest.header, startsWith('Filetype: '));
    });

    test('is one block per entry, in the order given', () {
      final text = DolphinManifest.build([entry('B'), entry('A')]);

      expect(RegExp('^Name: ', multiLine: true).allMatches(text).length, 2);
      expect(text.indexOf('Name: B'), lessThan(text.indexOf('Name: A')));
    });

    test('says the header once, however many blocks follow', () {
      final text = DolphinManifest.build([entry('A'), entry('B')]);

      expect('Filetype: '.allMatches(text).length, 1);
    });
  });

  group('a file that has been edited by hand', () {
    // The doc says malformed blocks are skipped rather than aborting, and no
    // animation is lost - both true. What is not true is that the stray lines
    // go nowhere: a block ends at the next `Name:`, not at the blank line, so
    // a paragraph with no name of its own is read as more of the block above.
    //
    // Pinned as it behaves. It is worth knowing because the firmware's own
    // parser is the other reader of this file, and if it ends a block at the
    // blank line then the app and the device disagree about a manifest the
    // user edited by hand. #171 holds the question.
    test('keeps every animation around a nameless paragraph', () {
      final read = entriesOf('''
${DolphinManifest.header}
Name: Good1
Weight: 4

Min level: 3
Weight: 9

Name: Good2
Weight: 5
''');

      expect(read.keys, ['Good1', 'Good2']);
      expect(read['Good2']!.weight, 5);
    });

    test('does not fold a nameless paragraph into the block above it', () {
      final read = entriesOf('Name: A\nWeight: 4\n\nWeight: 9\n');

      expect(
        read['A']!.weight,
        4,
        reason: 'the blank line ended the block; what follows is not its own',
      );
    });

    group('and is told how many paragraphs named nothing', () {
      test('none when every block has a name', () {
        expect(DolphinManifest.parse('Name: A\nWeight: 4\n').nameless, 0);
      });

      test('one for a paragraph of settings with no name', () {
        expect(
          DolphinManifest.parse('Name: A\nWeight: 4\n\nWeight: 9\n').nameless,
          1,
        );
      });

      test('one per paragraph, not one per line', () {
        expect(
          DolphinManifest.parse(
            'Name: A\n\nWeight: 9\nMin level: 2\n\nWeight: 3\n',
          ).nameless,
          2,
        );
      });

      // Settings before the first name are the same mistake at the top of the
      // file, and were already being dropped - silently.
      test('counts one written before any name', () {
        expect(DolphinManifest.parse('Weight: 4\n\nName: A\n').nameless, 1);
      });

      // A user's note between blocks is not a paragraph that lost its name.
      test('does not count a paragraph that holds no settings', () {
        expect(
          DolphinManifest.parse('Name: A\n\nsome note\n\nName: B\n').nameless,
          0,
        );
      });

      // Text pasted without a trailing newline ends mid-paragraph, so the
      // count has to be taken when the lines run out as well as at a blank
      // one. Every other case here happens to end with a newline.
      test('counts one the text ended on', () {
        expect(DolphinManifest.parse('Name: A\n\nWeight: 9').nameless, 1);
      });

      test('does not count the blank lines a manifest is built with', () {
        final text = DolphinManifest.build([entry('A'), entry('B')]);

        expect(DolphinManifest.parse(text).nameless, 0);
      });
    });

    test('drops settings written before any name', () {
      final read = entriesOf('Weight: 4\nName: A\n');

      expect(read.keys, ['A']);
      expect(read['A']!.weight, ManifestEntry.kDefaultWeight);
    });

    // A value that is not a number leaves the default rather than zeroing the
    // field: a weight of 0 is an animation that never plays, which is not
    // what a typo meant.
    test('leaves a default where a number was expected', () {
      final read = entriesOf('Name: A\nWeight: often\n');

      expect(read['A']!.weight, ManifestEntry.kDefaultWeight);
    });

    test('takes a negative number as written', () {
      final read = entriesOf('Name: A\nMin level: -1\n');

      expect(read['A']!.minLevel, -1);
    });

    // Windows line endings, or a line the user left a space on. The file
    // travels between a desktop, a phone and an SD card.
    //
    // What does the work is the `trim()` on each value, not the `trimRight()`
    // on the line - removing the latter changes nothing, so this pins the
    // outcome rather than the mechanism.
    test('tolerates trailing whitespace on a line', () {
      final read = entriesOf('Name: A  \r\nWeight: 6  \r\n');

      expect(read.keys, ['A']);
      expect(read['A']!.weight, 6);
    });

    // Entries are keyed by name, and the name is the on-device folder, so two
    // blocks claiming the same folder are one animation described twice.
    test('lets the last block win when a name repeats', () {
      final read = entriesOf('Name: A\nWeight: 1\n\nName: A\nWeight: 9\n');

      expect(read, hasLength(1));
      expect(read['A']!.weight, 9);
    });

    test('reads nothing out of nothing', () {
      expect(entriesOf(''), isEmpty);
      expect(entriesOf(DolphinManifest.header), isEmpty);
    });
  });
}
