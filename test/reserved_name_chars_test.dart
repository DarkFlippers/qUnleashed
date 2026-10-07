// One declaration of what a name may not contain, and everything that reads it.
//
// Before #266 there were two regexes for one set - a host one in `path.dart`
// that replaced nine characters, a device one in `seed_sub_file.dart` that
// reported the same nine plus the control range - and the English
// `seedNameIllegal` spelling the nine out a third time as words. (Only the
// English: `app_ru.arb` and `app_uk.arb` have never held a `seed` key.) The
// device regex was the correct one, and only its drift against its own test
// was caught by anything.
//
// So this file does two jobs. It restates the nine literally - a test is where
// an expectation is allowed to be spelled a second time, which is what makes a
// change to the constant a deliberate edit in two files rather than a typo. And
// it holds every rule that reads the constant to the same answer, over every
// character rather than a sample.
//
// What it cannot see: the paint editor's `_sanitizeName`, which refuses far
// more (`[^A-Za-z0-9_-]`) and then collapses runs of `_`. That is a different
// rule rather than a third copy of this one - what it produces is a Dolphin
// animation folder name, and the collapsing is tidiness and not a storage
// limit - so #266 leaves it where it is.
//
// What it also cannot see, structurally: whether a rule holds its own private
// copy of an identical regex. Giving `checkBaseName` back its old
// `_illegalInName` leaves every test here green, because an identical copy
// gives identical answers. These tests catch divergence, which is the failure
// that matters; the single-sourcing itself is held by review.
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
/// for over-refusal at some point: the dash because the Flipper's own keyboard
/// cannot type one, the dot because a `.sub` has one, the tilde and the
/// brackets because Windows tolerates them and some sanitizers do not. The
/// space is here because it looks like a candidate and is not one - the
/// device keyboard's shifted `_` produces it.
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

/// A string from the English ARB, read as text.
///
/// The ARB and not the generated class, because the assertion is about what
/// the source says: a translator reading `commonNameIllegal` must not find the
/// nine spelled out in it. What the *generated* class does with the
/// placeholder is a separate assertion, and that one does go through `l10n`.
String _arbString(String key) {
  final arb = jsonDecode(
    File('translations/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final value = arb[key];
  if (value is! String) {
    throw StateError('$key is not a string in app_en.arb');
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

    test('agrees with isControlNameChar about the control range', () {
      // The pattern writes the range as `\x00-\x1f\x7f` and
      // `isControlNameChar` writes it in Dart. Two spellings of one rule, and
      // the device rule reports a different problem depending on which one
      // answers - so a drift between them is a name refused with the wrong
      // sentence.
      for (var unit = 0; unit < 0x80; unit++) {
        final char = String.fromCharCode(unit);
        if (reservedNameChars.contains(char)) continue;
        expect(
          reservedNameCharsPattern.hasMatch(char),
          isControlNameChar(unit),
          reason: 'U+${unit.toRadixString(16).padLeft(4, '0')}',
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
      // What the host rule did not do on any of its eleven call sites, while
      // the device rule did. These segments are device names, app folder names
      // and release tags rather than anything the user typed, so a control
      // character in one means something upstream is wrong; `_` is the answer
      // that keeps the path writable on every host.
      expect(sanitizePathSegment('a\u0000b'), 'a_b');
      expect(sanitizePathSegment('a\nb'), 'a_b');
      expect(sanitizePathSegment('a\u001fb'), 'a_b');
      expect(sanitizePathSegment('a\u007fb'), 'a_b');
    });

    test('trims a control character off the ends rather than leaving a '
        'stand-in for it', () {
      // The edge case widening the class introduced. `.trim()` used to remove
      // a trailing newline because the old class did not match it; replacing
      // first would leave `name_` instead - and two of these call sites derive
      // a persistent per-device folder, so an install made under the old
      // spelling would look up a directory that no longer matches and read
      // empty. Trimming first keeps the old answer.
      expect(sanitizePathSegment('name\n'), 'name');
      expect(sanitizePathSegment('\rname'), 'name');
      expect(sanitizePathSegment('\n\n'), '');
      expect(sanitizePathSegment('  name  '), 'name');
      // A NUL is not whitespace, so `trim` does not reach it and `_` is the
      // answer. Pinned because it is the one edge where the two differ, and
      // because before #266 a NUL survived into the file name untouched.
      expect(sanitizePathSegment('name\u0000'), 'name_');
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
      for (final bad in _nine) {
        expect(
          SeedSubFile.checkBaseName('gate${bad}1'),
          SeedNameProblem.illegalCharacter,
          reason: '"$bad" should be refused',
        );
      }
    });

    test('reports a control character as its own problem', () {
      // Separate from the nine because the message for the nine lists what it
      // refuses and a control character has no printable form to list. A user
      // who pastes a newline and is shown the list of nine has been told
      // nothing about what they typed.
      for (final bad in ['\u0000', '\t', '\n', '\u001f', '\u007f']) {
        expect(
          SeedSubFile.checkBaseName('gate${bad}1'),
          SeedNameProblem.controlCharacter,
          reason:
              'U+${bad.codeUnitAt(0).toRadixString(16)} should be refused as '
              'a control character, not as one of the nine',
        );
      }
    });

    test('agrees with the host rule on every ASCII character', () {
      // Not a claim that the device rule reads the shared constant - an
      // identical private copy would pass this too. What it catches is the two
      // rules *diverging*, over the whole range rather than a sample, which is
      // the failure that reaches a user: a name the host rule would have
      // written and the device rule refuses, or the reverse.
      for (var unit = 0; unit < 0x80; unit++) {
        final char = String.fromCharCode(unit);
        final problem = SeedSubFile.checkBaseName('gate${char}1');
        final refused =
            problem == SeedNameProblem.illegalCharacter ||
            problem == SeedNameProblem.controlCharacter;
        expect(
          refused,
          reservedNameCharsPattern.hasMatch(char),
          reason:
              '"$char" (U+${unit.toRadixString(16).padLeft(4, '0')}) is '
              'judged differently by the two rules',
        );
      }
    });
  });

  group('the sentence shown to the user', () {
    test('takes the list rather than spelling it out', () {
      final english = _arbString('commonNameIllegal');
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

    test('does not name the nine in the control sentence either', () {
      // The sentence that cannot list what it refuses. If it grew the nine it
      // would be pointing the user at characters that are not the problem.
      final english = _arbString('commonNameControlChar');
      for (final bad in _nine) {
        expect(english, isNot(contains(bad)), reason: bad);
      }
    });

    test('interpolates what it is given', () {
      // The placeholder existing is not the same as it reaching the string:
      // gen-l10n is happy to generate a method whose argument is unused, which
      // is exactly what a translation that spells the nine out produces.
      expect(l10n.commonNameIllegal('ZZTOP'), contains('ZZTOP'));
    });
  });
}
