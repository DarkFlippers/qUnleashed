import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/path.dart';

/// What a name written to the Flipper may be.
///
/// The rule was `SeedSubFile.checkBaseName`, four directories down in the
/// Sub-GHz feature, and the three prompts in the file manager and the archive
/// that write a user-typed name to the device called nothing at all - so
/// `gate/one` reached the firmware and came back as a write failure naming no
/// cause. #277
///
/// These cases came with the rule. What stayed with the seed is its budget,
/// which is the only part of the rule that is Sub-GHz's.
///
/// The budget here is the Sub-GHz one wherever a case needs a short name,
/// because a 256-byte literal would make every row unreadable; the default is
/// covered on its own.
const _subGhzBytes = 63;

void main() {
  group('what a name may be', () {
    test('accepts what a user would reasonably type', () {
      for (final name in [
        'Genius_A0DC9330',
        'garage',
        'Gate 2',
        'front-gate',
        'v1.2',
        'a',
        'x' * _subGhzBytes,
      ]) {
        expect(
          deviceNameProblem(name, maxBytes: _subGhzBytes),
          isNull,
          reason: '"$name" should be accepted',
        );
      }
    });

    test('refuses an empty name, including one that is only spaces', () {
      expect(deviceNameProblem(''), DeviceNameProblem.empty);
      expect(deviceNameProblem('   '), DeviceNameProblem.empty);
    });

    test('refuses a name past the budget it was given', () {
      expect(
        deviceNameProblem('x' * (_subGhzBytes + 1), maxBytes: _subGhzBytes),
        DeviceNameProblem.tooLong,
      );
      // The same name against the volume's own limit, which is what a caller
      // that passes nothing gets.
      expect(deviceNameProblem('x' * (_subGhzBytes + 1)), isNull);
    });

    test('counts the default budget up to what FAT will hold', () {
      expect(deviceNameProblem('x' * deviceNameMaxBytes), isNull);
      expect(
        deviceNameProblem('x' * (deviceNameMaxBytes + 1)),
        DeviceNameProblem.tooLong,
      );
    });

    test('reports the rule whose fix the next refusal would not undo', () {
      // One table, because this is one invariant: when a name breaks two
      // rules, the message shown has to be the one the user can act on.
      //
      // The budget and the ASCII rule used to be the same subject - the limit
      // is a buffer and a Cyrillic letter is two bytes - so a long Cyrillic
      // name came back `tooLong`, sending the user to shorten something that
      // was never going to be accepted at any length. `.Ворота` reported as
      // `dotEdge` is the same dead end one problem over.
      //
      // A control character outranks even this, because its message names
      // something the user cannot see and this one does not.
      for (final (name, problem) in [
        // Over the budget as well as outside ASCII. The rows this file has to
        // carry, because no other test can make that pairing.
        ('я' * 32, DeviceNameProblem.nonAscii),
        ('🙂' * 16, DeviceNameProblem.nonAscii),
        // Comfortably inside it, so the refusal cannot be the length check in
        // disguise.
        ('Ворота', DeviceNameProblem.nonAscii),
        // Also dotted, also one of the nine.
        ('.Ворота', DeviceNameProblem.nonAscii),
        ('Ворота?', DeviceNameProblem.nonAscii),
        // One high character in an otherwise ASCII name - a non-breaking
        // space, which is the shape a paste from a web page arrives in.
        // Written as an escape, because an invisible literal leaves a reader
        // unable to see what is asserted.
        ('gate\u00a0one', DeviceNameProblem.nonAscii),
        ('gate\nЯ', DeviceNameProblem.controlCharacter),
      ]) {
        // The narrow budget, so the long rows below really are over it. With
        // the volume's 255 they are not, and a rule that judged the length
        // first would answer these the same way.
        expect(
          deviceNameProblem(name, maxBytes: _subGhzBytes),
          problem,
          reason: name,
        );
      }
    });

    test('refuses every character a FAT volume cannot carry', () {
      // Spelled out rather than a sample: a class that quietly stopped
      // matching one of these would let a save fail on the device instead,
      // reported as a write failure that names no cause.
      for (final bad in [r'\', '/', ':', '*', '?', '"', '<', '>', '|']) {
        expect(
          deviceNameProblem('gate${bad}1'),
          DeviceNameProblem.illegalCharacter,
          reason: '"$bad" should be refused',
        );
      }
      // A control character is refused too, but as its own problem: the
      // message for the nine lists them, and a newline has no printable form
      // to list. `test/reserved_name_chars_test.dart` walks the whole range.
      expect(
        deviceNameProblem('gate\u0000one'),
        DeviceNameProblem.controlCharacter,
      );
      expect(
        deviceNameProblem('gate\nnewline'),
        DeviceNameProblem.controlCharacter,
      );
    });

    test('refuses a leading or trailing dot', () {
      expect(deviceNameProblem('.hidden'), DeviceNameProblem.dotEdge);
      expect(deviceNameProblem('trailing.'), DeviceNameProblem.dotEdge);
      expect(deviceNameProblem('.'), DeviceNameProblem.dotEdge);
      expect(deviceNameProblem('..'), DeviceNameProblem.dotEdge);
    });

    test('judges the trimmed name, which is the one that gets written', () {
      // The surrounding spaces are dropped before the check and before the
      // write, so a name that is legal once trimmed is legal here.
      expect(deviceNameProblem('  garage  '), isNull);
      // And one that is not stays refused rather than being trimmed into
      // legality.
      expect(deviceNameProblem('  .hidden  '), DeviceNameProblem.dotEdge);
      // Dart's `trim` reaches past the ASCII space, so these arrive at the
      // check as plain `garage` too. Judging `raw` instead would refuse a name
      // that looks pure ASCII on screen, naming a character that is both
      // invisible and about to be removed anyway.
      for (final padded in [
        '\u00a0garage\u00a0',
        '\u3000garage',
        '\ufeffgarage',
        '\u0085garage',
      ]) {
        expect(deviceNameProblem(padded), isNull, reason: padded);
      }
    });
  });
}
