// One declaration of what a name may not contain, and everything that reads it.
//
// Before #266 there were three unrelated answers and a fourth in prose: a host
// regex in `path.dart` that replaced nine characters, a device regex in
// `seed_sub_file.dart` that reported the same nine plus the control range, a
// far stricter one in the paint editor, and `seedNameIllegal` spelling the nine
// out as words in every locale. The device one was the correct one, and only
// its drift against its own test was caught by anything.
//
// So this file does two jobs. It restates the nine literally - a test is where
// an expectation is allowed to be spelled a second time, which is what makes a
// change to the constant a deliberate edit in two files rather than a typo. And
// it checks that every rule in the app genuinely reads that one constant, by
// running each rule over every character rather than a sample.
//
// What it cannot see: the paint editor's `_sanitizeName`, which refuses far
// more (`[^A-Za-z0-9_-]`) and then collapses runs of `_`. That is a different
// rule rather than a third copy of this one - what it produces is a Dolphin
// animation folder name, and the collapsing is tidiness and not a storage
// limit - so #266 leaves it where it is.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/path.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_sub_file.dart';
import 'package:qunleashed/services/localization/l10n.dart';

/// The nine, spelled out. Windows reserves them and a FAT volume cannot hold
/// them, which is why one list serves a host path and a path on the Flipper.
const _nine = [r'\', '/', ':', '*', '?', '"', '<', '>', '|'];

/// Characters a name is allowed to carry, each of which has been a candidate
/// for over-refusal at some point: the space and the dash because the Flipper's
/// own keyboard offers neither, the dot because a `.sub` has one, the tilde and
/// the brackets because Windows tolerates them and some sanitizers do not.
const _legal = [
  ' ',
  '-',
  '_',
  '.',
  '~',
  '(',
  ')',
  '[',
  ']',
  '+',
  '=',
  ',',
  ';',
];

/// The English `seedNameIllegal`, read from the ARB rather than the generated
/// class, so a clean checkout does not have to build l10n first to run this.
String _arbIllegal() {
  final arb = jsonDecode(
    File('translations/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final value = arb['seedNameIllegal'];
  if (value is! String) {
    throw StateError('seedNameIllegal is not a string in app_en.arb');
  }
  return value;
}

void main() {
  group('the declaration', () {
    test('is exactly the nine', () {
      expect(reservedNameChars.split(''), _nine);
    });

    test('spells each of them once, for the user to read', () {
      expect(reservedNameCharsSpelled, _nine.join(' '));
    });
  });

  group('the pattern built from it', () {
    test('matches every reserved character and no legal one', () {
      // Every code unit below 0x80, not a sample. A character class is one
      // typo away from a range - a `-` added to the constant would silently
      // swallow everything between its neighbours - and the escaping is
      // generated, so this is the thing that notices.
      for (var unit = 0; unit < 0x80; unit++) {
        final char = String.fromCharCode(unit);
        final reserved =
            unit <= 0x1f || unit == 0x7f || reservedNameChars.contains(char);
        expect(
          reservedNameCharsPattern.hasMatch(char),
          reserved,
          reason: reserved
              ? 'U+${unit.toRadixString(16).padLeft(4, '0')} must be refused'
              : '"$char" (U+${unit.toRadixString(16).padLeft(4, '0')}) is a '
                    'legal character and must not be refused',
        );
      }
    });

    test('leaves non-ASCII alone', () {
      // The storage carries it - see `checkBaseName`'s note on `_CODE_PAGE
      // 850` - so a pattern that started matching it would be refusing names
      // that work, in the two locales this app is translated into.
      for (final char in ['я', 'Ї', 'ß', '漢', '🙂']) {
        expect(reservedNameCharsPattern.hasMatch(char), isFalse, reason: char);
      }
    });
  });

  group('the host rule', () {
    test('replaces every reserved character', () {
      for (final bad in _nine) {
        expect(
          sanitizePathSegment('a${bad}b'),
          'a_b',
          reason: '$bad should not survive into a host file name',
        );
      }
    });

    test('replaces a control character too, which is the #266 fix', () {
      // This is what the host rule did not do on any of its nine call sites,
      // while the device rule did. A newline or a NUL reaching a host path is
      // an "invalid argument" from the platform with nothing saying which
      // segment carried it - and these segments are device names, app folder
      // names and release tags, none of them typed by the user here.
      expect(sanitizePathSegment('a\u0000b'), 'a_b');
      expect(sanitizePathSegment('a\nb'), 'a_b');
      expect(sanitizePathSegment('a\u001fb'), 'a_b');
      expect(sanitizePathSegment('a\u007fb'), 'a_b');
    });

    test('keeps a legal character', () {
      for (final good in _legal) {
        expect(
          sanitizePathSegment('a${good}b'),
          'a${good}b',
          reason: '"$good" should survive',
        );
      }
    });
  });

  group('the device rule', () {
    test('reports every reserved character', () {
      for (final bad in [..._nine, '\u0000', '\n', '\u007f']) {
        expect(
          SeedSubFile.checkBaseName('gate${bad}1'),
          SeedNameProblem.illegalCharacter,
          reason: '"$bad" should be refused',
        );
      }
    });

    test('reads the shared pattern and not a copy of it', () {
      // The two rules agreeing on the nine is not the claim - they agreed
      // before #266 as well, by coincidence. The claim is that both read one
      // constant, so this walks the whole range the way the pattern test does
      // and holds the device rule to the same answer.
      for (var unit = 0x20; unit < 0x7f; unit++) {
        final char = String.fromCharCode(unit);
        // Only the character rule is under test here, so names that the dot
        // and length rules would answer first are skipped.
        if (char == '.') continue;
        expect(
          SeedSubFile.checkBaseName('gate${char}1') ==
              SeedNameProblem.illegalCharacter,
          reservedNameCharsPattern.hasMatch(char),
          reason: '"$char" is judged differently by the two rules',
        );
      }
    });
  });

  group('the sentence shown to the user', () {
    test('takes the list rather than spelling it out', () {
      final english = _arbIllegal();
      expect(
        english,
        contains('{chars}'),
        reason: 'the ARB must interpolate the list, not restate it',
      );
      for (final bad in _nine) {
        expect(
          english,
          isNot(contains(bad)),
          reason:
              'the ARB still names "$bad" itself, so removing it from '
              'reservedNameChars would leave this sentence behind',
        );
      }
    });

    test('interpolates what it is given', () {
      // The placeholder existing is not the same as it reaching the string:
      // gen-l10n is happy to generate a method whose argument is unused, which
      // is exactly what a translation that spells the nine out produces.
      expect(l10n.seedNameIllegal(reservedNameCharsSpelled), contains(r'\ /'));
      expect(l10n.seedNameIllegal('ZZTOP'), contains('ZZTOP'));
    });
  });
}
