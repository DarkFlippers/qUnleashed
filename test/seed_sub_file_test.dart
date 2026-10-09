// The `.sub` a recovered remote is written as.
//
// The expectation is not invented here: it is what the engine's own
// command-line build writes for the same recovery, captured by running it. The
// engine refuses to write that file unless re-encrypting the rebuilt frame
// reproduces the captured hop, so a file matching it byte for byte is one the
// firmware will transmit.
//
// What it cannot see: whether the firmware accepts the file. That needs a
// Flipper and a receiver.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';
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

/// Written by `faaccrack 3 A0DC9330 293AC619 1EECA414 CBCEFBA6 -f 868350000`,
/// the Genius known-answer vector the native probe also uses.
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
          SeedSubFile.checkBaseName(
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
    test('accepts what a user would reasonably type', () {
      for (final name in [
        'Genius_A0DC9330',
        'garage',
        'Gate 2',
        'front-gate',
        'v1.2',
        'a',
        'x' * SeedSubFile.maxBaseNameLength,
      ]) {
        expect(
          SeedSubFile.checkBaseName(name),
          isNull,
          reason: '"$name" should be accepted',
        );
      }
    });

    test('refuses an empty name, including one that is only spaces', () {
      expect(SeedSubFile.checkBaseName(''), SeedNameProblem.empty);
      expect(SeedSubFile.checkBaseName('   '), SeedNameProblem.empty);
    });

    test('refuses what the Sub-GHz app could not hold', () {
      // Exactly the buffer the firmware strncpy's an extension-less name
      // into, which leaves no room for the terminator. A longer name writes
      // fine over RPC and is mangled on the first rename there, which is the
      // surprise this refusal exists to prevent.
      expect(
        SeedSubFile.checkBaseName('x' * (SeedSubFile.maxBaseNameLength + 1)),
        SeedNameProblem.tooLong,
      );
    });

    test('reports a non-ASCII name as that, not as a length', () {
      // The byte budget and the ASCII rule used to be one subject: the limit
      // is a buffer, a Cyrillic letter is two bytes, so a long Cyrillic name
      // came back `tooLong` and the user was told to shorten something that
      // was never going to be accepted at any length. Both of these are over
      // the budget as well as outside ASCII, and only one of the two answers
      // is a fix the user can carry out.
      expect(SeedSubFile.checkBaseName('я' * 32), SeedNameProblem.nonAscii);
      expect(SeedSubFile.checkBaseName('🙂' * 16), SeedNameProblem.nonAscii);
      // And one that is comfortably inside the budget, so the refusal cannot
      // be the length check in disguise.
      expect(SeedSubFile.checkBaseName('Ворота'), SeedNameProblem.nonAscii);
      expect(SeedSubFile.checkBaseName('Außentor'), SeedNameProblem.nonAscii);
      // One high character in an otherwise ASCII name - a non-breaking space,
      // which is the shape a paste from a web page arrives in. Written as an
      // escape below rather than as the character, because an invisible
      // literal leaves a reader unable to see what is asserted.
      expect(
        SeedSubFile.checkBaseName('gate\u00a0one'),
        SeedNameProblem.nonAscii,
      );
    });

    test('reports a non-ASCII name before a dotted or illegal one', () {
      // The remaining precedence pairs, which the exhaustive switch does not
      // buy: a name can break two rules and only one message is shown, so the
      // first check decides what the user is told. `.Ворота` reported as
      // `dotEdge` sends them to delete the dot, after which the name is
      // refused again - the same dead end this change exists to remove, one
      // problem over.
      expect(SeedSubFile.checkBaseName('.Ворота'), SeedNameProblem.nonAscii);
      expect(SeedSubFile.checkBaseName('Ворота?'), SeedNameProblem.nonAscii);
      // The other way round: a control character outranks it, because that
      // message names something the user cannot see and this one does not.
      expect(
        SeedSubFile.checkBaseName('gate\nЯ'),
        SeedNameProblem.controlCharacter,
      );
    });

    test('judges the name after trimming, so invisible padding is not '
        'reported as a non-ASCII character', () {
      // `trim()` removes NBSP, ideographic space, BOM and NEL, so these reach
      // the check as plain `garage` and `pathFor` trims identically. Checking
      // `raw` instead would refuse a name that looks pure ASCII on screen,
      // naming a character that is both invisible and about to be removed.
      for (final padded in [
        '\u00a0garage\u00a0',
        '\u3000garage',
        '\ufeffgarage',
        '\u0085garage',
      ]) {
        expect(SeedSubFile.checkBaseName(padded), isNull, reason: padded);
      }
      expect(
        SeedSubFile.pathFor('\u00a0garage\u00a0'),
        '/ext/subghz/garage.sub',
      );
    });

    test('holds the budget to the buffer the firmware copies into', () {
      // `SUBGHZ_MAX_LEN_NAME` is 64 and `subghz_scene_save_name.c:73`
      // strncpy's the extension-less name into a `char[64]`, so 63 is the
      // longest name that keeps its terminator. Pinned as a literal, because
      // every other length assertion here is written in terms of the constant
      // and follows it wherever it moves - including to 64, which is the exact
      // off-by-one that writes fine over RPC and is then mangled by the first
      // rename on the device.
      //
      // This is what covers the budget. The *spelling* - bytes rather than
      // characters - cannot be covered through `checkBaseName` at all now that
      // non-ASCII is refused ahead of it, because for every name reaching the
      // length check the two counts are equal by construction. See
      // `maxBaseNameLength`, which says why it stays in bytes regardless.
      expect(SeedSubFile.maxBaseNameLength, 63);
      expect(utf8.encode('x' * 63).length, 63);
    });

    test('refuses every character a FAT volume cannot carry', () {
      // Spelled out rather than a sample: a class that quietly stopped
      // matching one of these would let a save fail on the device instead,
      // reported as a write failure that names no cause.
      for (final bad in [r'\', '/', ':', '*', '?', '"', '<', '>', '|']) {
        expect(
          SeedSubFile.checkBaseName('gate${bad}1'),
          SeedNameProblem.illegalCharacter,
          reason: '"$bad" should be refused',
        );
      }
      // A control character is refused too, but as its own problem: the
      // message for the nine lists them, and a newline has no printable form
      // to list. `test/reserved_name_chars_test.dart` walks the whole range.
      expect(
        SeedSubFile.checkBaseName('gate\u0000one'),
        SeedNameProblem.controlCharacter,
      );
      expect(
        SeedSubFile.checkBaseName('gate\nnewline'),
        SeedNameProblem.controlCharacter,
      );
    });

    test('refuses a leading or trailing dot', () {
      expect(SeedSubFile.checkBaseName('.hidden'), SeedNameProblem.dotEdge);
      expect(SeedSubFile.checkBaseName('trailing.'), SeedNameProblem.dotEdge);
      expect(SeedSubFile.checkBaseName('.'), SeedNameProblem.dotEdge);
      expect(SeedSubFile.checkBaseName('..'), SeedNameProblem.dotEdge);
    });

    test('judges the trimmed name, which is the one that gets written', () {
      // The surrounding spaces are dropped before the check and before the
      // write, so a name that is legal once trimmed is legal here.
      expect(SeedSubFile.checkBaseName('  garage  '), isNull);
      // And one that is not stays refused rather than being trimmed into
      // legality.
      expect(SeedSubFile.checkBaseName('  .hidden  '), SeedNameProblem.dotEdge);
    });

    test('accepts a name that carries the extension, deliberately', () {
      // It becomes `gate.sub.sub`, which is why the field shows the extension
      // as a fixed suffix rather than leaving the user to type it. Nothing
      // refuses it, and this records that as the choice it is: the firmware
      // lists `gate.sub.sub` perfectly well, it just looks silly.
      expect(SeedSubFile.checkBaseName('gate.sub'), isNull);
    });
  });
}
