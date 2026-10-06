// Guards on the generated SubGHz seed-recovery engine, which is machine output.
//
// Its readable source carries the four manufacture keys and is deliberately not
// in this repository, so nothing here can diff the two - the author's own
// equivalence script does that, on a machine with the private kit. What this
// file can do is hold the shipped artefact to the structural properties the
// obfuscation is supposed to give it, which is enough to catch a regeneration
// that went wrong.
//
// It names none of the secrets. Asserting that a manufacture key is absent by
// spelling it out would put the key back in the repo in readable form and
// defeat the entire exercise. The assertions are about the shape of the whole
// file instead.
//
// What it cannot see:
//
//  * Whether the engine still computes the right thing. That is
//    `.github/scripts/check_faaccrack_engine.sh`, which runs the engine's three
//    internal known-answer checks.
//  * Whether any particular constant is unrecoverable. It is not: anyone who
//    can build this can read every constant out of the binary. These passes
//    raise the cost of reading them out of the *source*, and that is all they
//    were for.
//  * A partially-populated reserved set, where some names were renamed and
//    others not. The second group below catches the total failure; only the
//    private equivalence script catches a partial one.
//
// There is deliberately no assertion on how *many* literals were split. A count
// floor would be a proxy for "the pass ran", and the first test below asserts
// that directly - a pass that covered only part of the file leaves unsplit
// literals behind, which is what fails. A floor set below today's figure would
// pass in exactly that case while looking like protection.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'faaccrack_sources.dart';

/// An integer literal the obfuscator has split into a pair the compiler folds
/// back at build time, e.g. `(0x775E0CC3^0x775E0EC3)`.
///
/// The suffix alternation is load-bearing: the engine's 64-bit constants carry
/// `u`, `ull` and `ll`, and a pattern without them reports every one of those
/// as an unsplit literal.
final _xorPair = RegExp(
  r'\(\s*0x[0-9A-Fa-f]+(?:[uU](?:[lL]{1,2})?|[lL]{1,2}[uU]?)?'
  r'\s*\^\s*'
  r'0x[0-9A-Fa-f]+(?:[uU](?:[lL]{1,2})?|[lL]{1,2}[uU]?)?\s*\)',
);

/// The string blob and its decoder: `static char O0lIlIlO[1345]={...}` and the
/// constructor that XORs it back before `main`. The name is junk and changes on
/// every regeneration, so only the shape is matched.
final _blobDeclaration = RegExp(r'static char (\w+)\[(\d+)\]=\{');

/// Spellings that only survive because the obfuscator had a working `cc` to
/// build its reserved set from. With no reserved set every one of these is
/// renamed along with the engine's own identifiers, so any absence means the
/// generated file came from a run whose `header preprocess failed` warning
/// nobody read - and `cobf.py` still reports a plausible byte count for it.
const _libcSpellings = [
  'uint32_t',
  'uint64_t',
  'printf',
  'fprintf',
  'stderr',
  'memset',
  'strtoul',
  'pthread_create',
  'pthread_join',
  'getenv',
  'clock',
  'NULL',
  'CLOCKS_PER_SEC',
  '__ATOMIC_RELAXED',
];

void main() {
  final engine = faaccrackEngine();
  // Everything after the banner comment. The banner is the one piece of
  // readable text in the file and is deliberate.
  final body = engine.substring(engine.indexOf('*/') + 2);
  final withoutPairs = engine.replaceAll(_xorPair, '(P)');
  final blob = _blobDeclaration.firstMatch(engine);

  group('the obfuscation passes all ran', () {
    test('every integer literal is split into an XOR pair', () {
      // Three digits, because the only naked hex left is a two-digit mask in
      // the blob decoder. Anything longer is an unsplit constant - and the
      // manufacture keys, the KeeLoq NLF constant and the Faac ending are all
      // longer, the keys by a lot: a 64-bit value is sixteen digits.
      expect(
        RegExp(r'0x[0-9A-Fa-f]{3,}')
            .allMatches(withoutPairs)
            .map((m) => m.group(0))
            .toSet(),
        isEmpty,
        reason:
            'unsplit hex literals in $faaccrackEnginePath - the literal pass '
            'did not cover the whole file',
      );
    });

    test('the string blob and its decoder are both present', () {
      expect(blob, isNotNull, reason: 'no string blob in $faaccrackEnginePath');
      expect(
        engine.contains('__attribute__((constructor))'),
        isTrue,
        reason: 'the blob is never decoded - no constructor',
      );
    });

    test('no decimal literal is larger than the blob it describes', () {
      // Every loop bound and mask became hex, so the only decimals left are the
      // blob's own bytes (0..255) and its declared length. A larger one means a
      // literal the pass missed.
      final blobLength = int.parse(blob!.group(2)!);
      expect(
        RegExp(r'(?<![\w.])(\d+)(?![\w.])')
            .allMatches(withoutPairs)
            .map((m) => int.parse(m.group(1)!))
            .where((value) => value > blobLength)
            .toSet(),
        isEmpty,
        reason: 'undisguised decimal literals',
      );
    });

    test('the only strings left are the include names', () {
      // Include directives keep their own text - they have to resolve at
      // preprocessing time - so the quoted includes are expected, along with
      // the one pragma the generator emits. Nothing else is.
      expect(
        RegExp(r'"((?:[^"\\]|\\.)*)"')
            .allMatches(engine)
            .map((m) => m.group(1)!)
            .toSet(),
        {...faaccrackQuotedIncludes.keys, '-Wformat-security'},
      );
    });

    test('no comment survives in the body', () {
      expect(body.contains('/*'), isFalse);
      expect(body.contains('//'), isFalse);
    });
  });

  test('the libc spellings survived, so the generator had a working cc', () {
    // One assertion rather than one per name: the diagnosis is the same
    // whichever is missing, and this way the failure names every absent
    // spelling at once instead of only the first.
    expect(
      _libcSpellings.where((spelling) => !engine.contains(spelling)),
      isEmpty,
      reason:
          'these were renamed, so the reserved set was empty: the generating '
          'run could not find a `cc` and only warned. See $faaccrackNotesPath.',
    );
  });

  test('the directory holds nothing but the files it is meant to', () {
    // The real guard against the private engine source arriving. `.gitignore`
    // names three basenames, which stops nothing under a fourth name and
    // nothing at all under `git add -f` - and what must not land is the four
    // manufacture keys in readable form, under *any* name. An allowlist does
    // not have to predict what that file would be called.
    final found = Directory(faaccrackDir)
        .listSync(recursive: true)
        .whereType<File>()
        .map(
          (f) =>
              f.path.replaceAll(r'\', '/').replaceFirst('$faaccrackDir/', ''),
        )
        .toSet();
    expect(
      found.difference(faaccrackAllowedFiles),
      isEmpty,
      reason:
          'unexpected files under $faaccrackDir. If one of these is the '
          "engine's readable source, a copy of it, or anything else carrying "
          'the manufacture keys, it must not be committed - see '
          '$faaccrackNotesPath. If it is a legitimate new file, add it to '
          'faaccrackAllowedFiles in test/faaccrack_sources.dart.',
    );
  });
}
