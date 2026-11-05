// The manufacturers the tool claims to handle, against the ones it handles.
//
// `SeedManufacturer` and the sentence in `toolSeedRecoverySubtitle` are two
// statements of one list, written in two files by two different people - the
// enum by whoever adds a mode, the sentence by whoever edits `app_en.arb`.
// Nothing derives either from the other, and until this file nothing compared
// them: the rule lived in the ARB description as prose, "BFT is solved but not
// listed", which nothing enforced.
//
// What it catches is a manufacturer added to the enum without the sentence
// gaining it, and the reverse - a name left in the sentence that no enum value
// solves, which is the likelier mistake because the sentence is in a file
// translators also touch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

import 'arb.dart';

/// The English subtitle, read out of the ARB rather than the generated class.
///
/// The generated l10n is gitignored, so a test that imported `L10n` would be
/// asserting against something a clean checkout has to build first. The ARB is
/// the source the Crowdin guard protects, and the only file this change may
/// hand-edit.
///
/// Through [arbStrings] rather than a regex of its own: that is where the
/// metadata rule lives, and a decoded string is the whole value. A pattern
/// stopping at the first `"` would read a reworded sentence containing an
/// escaped quote back truncated, and this test would then pass on a shorter
/// sentence than the app shows.
String _subtitle() {
  final subtitle = arbStrings(
    File('$kArbDir/app_en.arb'),
  )['toolSeedRecoverySubtitle'];
  if (subtitle == null) {
    throw StateError('toolSeedRecoverySubtitle is not in $kArbDir/app_en.arb');
  }
  return subtitle;
}

/// How a manufacturer's name appears in a prose list.
///
/// The first word of the label: the subtitle says "FAAC" where the enum says
/// "FAAC SLH", because the sentence names the maker and the label names the
/// protocol variant the capture file spells.
String _inProse(SeedManufacturer m) => m.label.split(' ').first;

/// The sentence the enum implies, which is what the ARB must hold.
///
/// Built from the enum rather than matched against it word by word: harvesting
/// capitalised words needed a regex plus a hand-kept list of the sentence's own
/// non-names, and the documented way out of a failure was to add a word to that
/// list - which is also how a real failure gets silenced. Rendering the
/// sentence instead makes both directions one string comparison, and pins the
/// order the engine numbers them in for free.
///
/// The cost is that rewording the English fails this test. That is the right
/// cost: the failure prints both sentences, and the fix is to reword the
/// template here too.
String _impliedSubtitle() {
  final names = SeedManufacturer.values.map(_inProse).toList();
  final list = '${names.take(names.length - 1).join(', ')} and ${names.last}';
  return 'Recover $list remotes';
}

void main() {
  test('the subtitle names exactly the manufacturers the tool solves', () {
    expect(
      _subtitle(),
      _impliedSubtitle(),
      reason:
          'the subtitle and SeedManufacturer disagree about which remotes this '
          'tool recovers. A name only the enum has means the tool lists fewer '
          'than it solves; a name only the sentence has means it offers a '
          'recovery that comes back as a manufacturer this build has no key for',
    );
  });

  test('a capture naming any of them resolves', () {
    // Narrow: what this can fail on is a fifth value whose label normalises to
    // the same thing as an existing one, which would make `fromLabel` return
    // the wrong manufacturer and pick the wrong manufacture key. The
    // normalisation itself - `faac_slh`, `FaacSlh` - is covered in
    // `test/seed_capture_format_test.dart`.
    for (final manufacturer in SeedManufacturer.values) {
      expect(
        SeedManufacturer.fromLabel(manufacturer.label),
        manufacturer,
        reason: '${manufacturer.label} must still be recognised',
      );
    }
  });
}
