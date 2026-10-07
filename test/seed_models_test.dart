// The manufacturers the tool claims to handle, against the ones it handles.
//
// `SeedManufacturer.advertised` and the sentence in `toolSeedRecoverySubtitle`
// are two statements of one decision, and only one of them is read by the code.
// BFT is solved by the engine and deliberately left out of the subtitle,
// because the firmware recovers those itself - so "the subtitle lists all of
// them" is not the rule, and a plain completeness check would be wrong.
//
// Without this, the ARB description carried the rule as the words "Do not add
// it back", which nothing enforces. Re-advertising BFT is a one-word edit in a
// file translators also touch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

const _arbPath = 'translations/app_en.arb';

/// The English subtitle, read out of the ARB rather than the generated class.
///
/// The generated l10n is gitignored, so a test that imported `L10n` would be
/// asserting against something a clean checkout has to build first. The ARB is
/// the source the Crowdin guard protects, and the only file this change may
/// hand-edit.
String _subtitle() {
  final arb = File(_arbPath).readAsStringSync();
  final match = RegExp(r'"toolSeedRecoverySubtitle": "([^"]*)"')
      .firstMatch(arb);
  if (match == null) {
    throw StateError('toolSeedRecoverySubtitle is not in $_arbPath');
  }
  return match.group(1)!;
}

/// How a manufacturer's name appears in a prose list.
///
/// The first word of the label: the subtitle says "FAAC" where the enum says
/// "FAAC SLH", because the sentence names the maker and the label names the
/// protocol variant the capture file spells.
String _inProse(SeedManufacturer m) => m.label.split(' ').first;

void main() {
  test('every advertised manufacturer is named in the subtitle', () {
    final subtitle = _subtitle();
    final advertised = SeedManufacturer.values.where((m) => m.advertised);
    expect(advertised, isNotEmpty, reason: 'the tool offers something');
    for (final manufacturer in advertised) {
      expect(
        subtitle,
        contains(_inProse(manufacturer)),
        reason:
            '${manufacturer.name} is advertised but the subtitle does not say '
            'so, so the tool lists fewer remotes than it solves',
      );
    }
  });

  test('no unadvertised manufacturer is named in the subtitle', () {
    final subtitle = _subtitle();
    final hidden = SeedManufacturer.values.where((m) => !m.advertised);
    expect(
      hidden,
      isNotEmpty,
      reason:
          'if nothing is hidden any more, this file and the `advertised` field '
          'have no job - delete both rather than leaving a test that cannot '
          'fail',
    );
    for (final manufacturer in hidden) {
      expect(
        subtitle,
        isNot(contains(_inProse(manufacturer))),
        reason:
            '${manufacturer.name} is in the subtitle but is not advertised. '
            'The firmware already recovers it; see the note on the enum value.',
      );
    }
  });

  test('a capture naming an unadvertised manufacturer still resolves', () {
    // The whole reason the enum value stays. `fromLabel` returning null makes
    // the parser refuse the capture as a manufacturer this build has no key
    // for, which would be a lie.
    for (final manufacturer in SeedManufacturer.values) {
      expect(
        SeedManufacturer.fromLabel(manufacturer.label),
        manufacturer,
        reason: '${manufacturer.label} must still be recognised',
      );
    }
  });
}
