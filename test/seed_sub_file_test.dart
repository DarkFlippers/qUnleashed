// The `.sub` a recovered remote is written as.
//
// The expectations are not invented here: each is what the engine's own
// command-line build writes for the same recovery, captured by running it. The
// engine refuses to write that file unless re-encrypting the rebuilt frame
// reproduces the captured hop, so a file matching it byte for byte is one the
// firmware will transmit.
//
// Which build matters, for the two KeeLoq ones. They come from the engine's
// readable source *after* it learned to reverse a KeeLoq frame. The obfuscated
// copy in `lib/modules/cpp/faaccrack/` predates that, so building the CLI from
// the in-repo engine and re-running these commands reproduces every line
// except `Key:`, which comes back unreversed. That is the stale artifact, not a
// wrong fixture here - and it reaches nothing, because the library build
// renames `main` away (`CMakeLists.txt`) and the app writes the `.sub` itself.
//
// What none of it can see: whether the firmware accepts the file. That needs a
// Flipper and a receiver.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';
import 'package:qunleashed/components/path.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_sub_file.dart';

/// A recovery that came back verified, which is the only kind that may be
/// written.
SeedResult _found({
  required int seed,
  required int frameHop,
  int hopsUsed = 3,
}) => (
  outcome: SeedOutcome.found,
  seed: seed,
  lrkey: 0,
  counter: 0,
  frameHop: frameHop,
  hopsUsed: hopsUsed,
);

/// Written by `faaccrack 3 A0DC9330 293AC619 1EECA414 CBCEFBA6 -o genius.sub
/// -f 868350000`, the Genius known-answer vector the native probe also uses.
/// Without `-o` the engine solves and prints but writes nothing.
const _engineWroteGenius = '''
Filetype: Flipper SubGhz Key File
Version: 1
Frequency: 868350000
Preset: FuriHalSubGhzPresetOok650Async
Protocol: Faac SLH
Bit: 64
Key: A0 DC 93 30 CB CE FB A6
Seed: 00 00 07 89
Manufacture: Genius
''';

/// Written by `faaccrack 2 200342E2 2F62BE4B 1895D794 367AEB49 -o bft.sub -f
/// 433920000`, the BFT known-answer vector.
///
/// The key is the frame `200342E2367AEB49` reversed over all 64 bits, so a
/// reader can recompute it. See [SeedManufacturer.framesAreBitReversed] for
/// what the firmware does with it.
const _engineWroteBft = '''
Filetype: Flipper SubGhz Key File
Version: 1
Frequency: 433920000
Preset: FuriHalSubGhzPresetOok650Async
Protocol: KeeLoq
Bit: 64
Key: 92 D7 5E 6C 47 42 C0 04
Seed: 00 00 04 56
Manufacture: BFT
''';

/// The `Key:` line of what `faaccrack 4 20345678 4AB86AAC 04C40F30 A1988133 -o
/// erreka.sub -f 433920000` wrote: the frame `20345678A1988133` reversed.
///
/// The other KeeLoq manufacturer, so that the reversal is pinned by protocol
/// and not by one enum value. Only the key, because that is this vector's whole
/// job - [_engineWroteBft] already holds the KeeLoq header byte for byte, and a
/// second full-file fixture would report a change to `Preset:` under the name
/// of the reversal.
const _engineWroteErrekaKey = 'Key: CC 81 19 85 1E 6A 2C 04';

void main() {
  group('render', () {
    test('matches what the engine itself writes', () {
      expect(
        SeedSubFile.render(
          result: _found(seed: 0x00000789, frameHop: 0xCBCEFBA6),
          manufacturer: SeedManufacturer.genius,
          fix: 0xA0DC9330,
          frequencyHz: 868350000,
        ),
        _engineWroteGenius,
      );
    });

    test('turns a KeeLoq frame round, as the engine does', () {
      // Not a formatting choice - see `SeedManufacturer.framesAreBitReversed`
      // for what the firmware does with a frame written the other way round.
      expect(
        SeedSubFile.render(
          result: _found(seed: 0x00000456, frameHop: 0x367AEB49),
          manufacturer: SeedManufacturer.bft,
          fix: 0x200342E2,
          frequencyHz: 433920000,
        ),
        _engineWroteBft,
      );
      expect(
        SeedSubFile.render(
          result: _found(seed: 0x0600A0BC, frameHop: 0xA1988133),
          manufacturer: SeedManufacturer.erreka,
          fix: 0x20345678,
          frequencyHz: 433920000,
        ),
        contains(_engineWroteErrekaKey),
      );
    });

    test('puts the fixed code in the top half of the key', () {
      // The frame is one 64-bit value: the fixed code above, the rolling half
      // below. Getting the halves the wrong way round still produces a
      // plausible file, which is why this is asserted separately.
      final rendered = SeedSubFile.render(
        result: _found(seed: 0x00000123, frameHop: 0x9ABCDEF0),
        manufacturer: SeedManufacturer.faacSlh,
        fix: 0x12345678,
        frequencyHz: 433920000,
      );
      expect(rendered, contains('Key: 12 34 56 78 9A BC DE F0'));
      expect(rendered, contains('Seed: 00 00 01 23'));
    });

    test('says a zero seed is real, for the protocols that need telling', () {
      // Faac reads a zero seed as "unknown" unless the file says otherwise, so
      // this is the one case where a genuine value looks like an absent one.
      expect(
        SeedSubFile.render(
          result: _found(seed: 0, frameHop: 0x027AC36E),
          manufacturer: SeedManufacturer.genius,
          fix: 0xA0DC9330,
          frequencyHz: 868350000,
        ),
        contains('AllowZeroSeed: true'),
      );
      // KeeLoq reads it back for any manufacturer, so the key would be noise.
      expect(
        SeedSubFile.render(
          result: _found(seed: 0, frameHop: 0x367AEB49),
          manufacturer: SeedManufacturer.bft,
          fix: 0x200342E2,
          frequencyHz: 433920000,
        ),
        isNot(contains('AllowZeroSeed')),
      );
    });

    test('carries the protocol and manufacturer the firmware reads back', () {
      // Two manufacturers share each protocol, so `Manufacture` is what tells
      // them apart - a Genius file written as FAAC_SLH decrypts to nothing.
      for (final (manufacturer, protocol) in [
        (SeedManufacturer.faacSlh, 'Faac SLH'),
        (SeedManufacturer.genius, 'Faac SLH'),
        (SeedManufacturer.bft, 'KeeLoq'),
        (SeedManufacturer.erreka, 'KeeLoq'),
      ]) {
        final rendered = SeedSubFile.render(
          result: _found(seed: 0x99AABBCC, frameHop: 0x55667788),
          manufacturer: manufacturer,
          fix: 0x11223344,
          frequencyHz: 433920000,
        );
        expect(rendered, contains('Protocol: $protocol'));
        expect(rendered, contains('Manufacture: ${manufacturer.label}'));
      }
    });
  });

  group('refusing to write', () {
    test('an unverified recovery cannot be rendered', () {
      // The seed is real and worth showing; the frame did not rebuild, so a
      // file carrying it would be accepted by the firmware and transmit
      // nothing. The engine makes this a status rather than a flag so a caller
      // cannot forget - and this is what stops the renderer handing that
      // forgettability back.
      expect(
        () => SeedSubFile.render(
          result: (
            outcome: SeedOutcome.unverified,
            seed: 0x00000789,
            lrkey: 0,
            counter: 0,
            frameHop: 0xCBCEFBA6,
            hopsUsed: 3,
          ),
          manufacturer: SeedManufacturer.genius,
          fix: 0xA0DC9330,
          frequencyHz: 868350000,
        ),
        throwsArgumentError,
      );
    });

    test('nor can any outcome that found nothing', () {
      for (final outcome in SeedOutcome.values) {
        if (outcome == SeedOutcome.found) continue;
        expect(
          () => SeedSubFile.render(
            result: (
              outcome: outcome,
              seed: 1,
              lrkey: 0,
              counter: 0,
              frameHop: 2,
              hopsUsed: 3,
            ),
            manufacturer: SeedManufacturer.genius,
            fix: 0xA0DC9330,
            frequencyHz: 868350000,
          ),
          throwsArgumentError,
          reason: '$outcome must not produce a file',
        );
      }
    });
  });

  group('baseName', () {
    test('names the remote by its fixed code', () {
      expect(
        SeedSubFile.baseName(
          manufacturer: SeedManufacturer.genius,
          fix: 0xA0DC9330,
        ),
        'Genius_A0DC9330',
      );
    });

    test('is stable, so re-recovering a remote does not accumulate copies', () {
      String nameFor(int fix) => SeedSubFile.baseName(
        manufacturer: SeedManufacturer.faacSlh,
        fix: fix,
      );
      expect(nameFor(0x12345674), nameFor(0x12345674));
      expect(nameFor(0x12345674), isNot(nameFor(0x12345675)));
    });

    test('leaves the label as one word', () {
      // Tidiness, not a storage rule: "FAAC SLH" has a space, and a generated
      // name reads better without it. checkBaseName accepts a space the user
      // types, which is the rule the device actually has.
      expect(
        SeedSubFile.baseName(
          manufacturer: SeedManufacturer.faacSlh,
          fix: 0x00000001,
        ),
        'FAACSLH_00000001',
      );
    });

    test('carries no extension; pathFor adds it', () {
      // The dialog offers this and shows the extension as a fixed suffix, so
      // the two halves have to agree about which one carries the dot.
      const manufacturer = SeedManufacturer.genius;
      const fix = 0xA0DC9330;
      final base = SeedSubFile.baseName(manufacturer: manufacturer, fix: fix);
      expect(base, isNot(endsWith(SeedSubFile.fileExtension)));
      expect(SeedSubFile.pathFor(base), endsWith('$base.sub'));
    });

    test('the suggested name is one the rules accept', () {
      // Otherwise the dialog opens on a name its own Save button refuses.
      for (final manufacturer in SeedManufacturer.values) {
        expect(
          SeedSubFile.nameRule.check(
            SeedSubFile.baseName(manufacturer: manufacturer, fix: 0xA0DC9330),
          ),
          isNull,
          reason: '${manufacturer.label} suggests a name it would refuse',
        );
      }
    });
  });

  group('pathFor', () {
    test('puts the file where the Sub-GHz app looks', () {
      expect(SeedSubFile.pathFor('garage'), '/ext/subghz/garage.sub');
    });

    test('trims, so the path matches the name that was checked', () {
      // checkBaseName judges the trimmed name. If this did not trim too, a
      // name with a trailing space would pass the check and then be written to
      // a different path than the one the collision check asked about.
      expect(SeedSubFile.pathFor('  garage  '), SeedSubFile.pathFor('garage'));
    });
  });

  group('checkBaseName', () {
    // The rule itself moved to `deviceNameProblem`, with its table of which
    // refusal wins; `test/device_name_rule_test.dart` holds it. What is
    // Sub-GHz's is the budget, so that is what is left here. #277
    test('holds the budget to the buffer the firmware copies into', () {
      // `SUBGHZ_MAX_LEN_NAME` is 64 and `subghz_scene_save_name.c` strncpy's
      // the extension-less name into a `char[64]`, so 63 is the longest name
      // that keeps its terminator. Pinned as a literal, because every other
      // length assertion is written in terms of the constant and follows it
      // wherever it moves - including to 64, the exact off-by-one that writes
      // fine over RPC and is mangled by the first rename on the device.
      expect(SeedSubFile.maxBaseNameLength, 63);
    });

    test('passes its own budget rather than the volume default', () {
      // The one thing the delegation can get wrong. A name this long is fine
      // for the storage and too long for the Sub-GHz app, so it separates
      // "called the shared rule" from "called it with 63".
      final tooLongForSubGhz = 'x' * (SeedSubFile.maxBaseNameLength + 1);

      expect(
        SeedSubFile.nameRule.check(tooLongForSubGhz),
        DeviceNameProblem.tooLong,
      );
      // And exactly the budget is accepted, which is what makes this an
      // off-by-one test rather than a "passes something" one: `maxBytes:
      // maxBaseNameLength - 1` satisfies the row above on its own.
      expect(
        SeedSubFile.nameRule.check('x' * SeedSubFile.maxBaseNameLength),
        isNull,
      );
      expect(
        deviceNameProblem(tooLongForSubGhz, maxBytes: deviceNameMaxBytes),
        isNull,
      );
    });

    test('accepts a name that carries the extension, deliberately', () {
      // It becomes `gate.sub.sub`, which is why the field shows the extension
      // as a fixed suffix rather than leaving the user to type it. Nothing
      // refuses it, and this records that as the choice it is: the firmware
      // lists `gate.sub.sub` perfectly well, it just looks silly.
      expect(SeedSubFile.nameRule.check('gate.sub'), isNull);
    });
  });
}
