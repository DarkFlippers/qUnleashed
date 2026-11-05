// The map from the engine's status codes to the outcomes this app switches on.
//
// It exists because nothing derives one from the other: this project has no
// code generation, so the numbers are retyped in Dart from
// `enum faaccrack_status` in lib/modules/cpp/faaccrack/faaccrack.h. A code the
// C side adds without a case here lands in `engineFault`, which reads as "this
// build is wrong" rather than as an answer about the remote - the safe default,
// and still worth noticing.
//
// The numbers below are written out rather than imported, deliberately. A test
// that read the same constants the code under test uses would pass whatever
// they were changed to.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/faaccrack_recoverer.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

void main() {
  group('seedOutcomeFor', () {
    const expected = <int, SeedOutcome>{
      0: SeedOutcome.found,
      -2: SeedOutcome.engineFault, // bad arguments: a fault in this app
      -3: SeedOutcome.stopped,
      -4: SeedOutcome.engineBusy,
      -5: SeedOutcome.unverified,
      -10: SeedOutcome.nothingMatched,
      -20: SeedOutcome.engineSelfTestFailed, // NLF network
      -21: SeedOutcome.engineSelfTestFailed, // KeeLoq vector
      -22: SeedOutcome.engineSelfTestFailed, // Erreka shuffle
    };

    expected.forEach((status, outcome) {
      test(
        '$status is $outcome',
        () => expect(seedOutcomeFor(status), outcome),
      );
    });

    test('an unknown code is this build being wrong, not a verdict', () {
      // The one thing that must never happen is a status the app does not know
      // being reported as "no seed exists", which would send a user away from a
      // remote that is perfectly recoverable.
      for (final status in [-1, -6, -11, -23, -99, 7]) {
        expect(
          seedOutcomeFor(status),
          SeedOutcome.engineFault,
          reason: '$status should not be mistaken for an answer',
        );
      }
    });

    test('every self-test code in the range maps to the same outcome', () {
      // The engine reports which of its three startup checks failed, and all
      // three mean the same thing to a user: this build is broken. A fourth
      // check added inside the range has to keep saying that rather than
      // becoming a generic fault.
      for (var status = -22; status <= -20; status++) {
        expect(seedOutcomeFor(status), SeedOutcome.engineSelfTestFailed);
      }
    });
  });

  group('seedResultIsMeaningful', () {
    test('only a find and an unverified find carry a result', () {
      // Against a literal set, not against the same expression the function
      // evaluates - that version could not fail for the reason its name gives,
      // which is the trap CLAUDE.md's last anti-pattern names.
      //
      // The engine zeroes the struct on every other path, and zero is a legal
      // seed, so the outcome is the only thing that says it means anything.
      const carriesAResult = {SeedOutcome.found, SeedOutcome.unverified};
      expect(
        SeedOutcome.values.where(seedResultIsMeaningful).toSet(),
        carriesAResult,
      );
    });
  });

  group('SeedManufacturer', () {
    test('the mode numbers are the ones the engine takes', () {
      // Transcribed from the generated engine, which compares its own literals.
      // The native probe's known-answer vectors are what actually hold these in
      // step; this only catches a typo on the Dart side.
      expect(
        {for (final m in SeedManufacturer.values) m.label: m.mode},
        {'FAAC SLH': 1, 'BFT': 2, 'Genius': 3, 'Erreka': 4},
      );
    });

    test('the Manufacture each one writes is the keystore entry name', () {
      // Closed-world: these are matched by `strcmp` against keystore entries,
      // so a fifth manufacturer typed to this app's taste rather than the
      // keystore's gets FAAC's key through the Faac fallback, or no key at all.
      // The firmware writes these same four in `subghz_gen_info.c`.
      expect(
        {for (final m in SeedManufacturer.values) m.label: m.inFile},
        {
          'FAAC SLH': 'FAAC_SLH',
          'BFT': 'BFT',
          'Genius': 'Genius',
          'Erreka': 'Erreka',
        },
      );
    });

    test('each manufacturer is paired with the right frame layout', () {
      // Closed-world, like the mode map above. The layout is now a value, so a
      // mis-cased protocol is a compile error rather than something a test has
      // to catch - what is still hand-typed, and what this pins, is which of
      // the two each manufacturer was given. Pairing Erreka with Faac would
      // write its frame unreversed, which the firmware reads as a different
      // remote.
      expect(
        {for (final m in SeedManufacturer.values) m.label: m.protocol},
        {
          'FAAC SLH': SeedProtocol.faacSlh,
          'BFT': SeedProtocol.keeloq,
          'Genius': SeedProtocol.faacSlh,
          'Erreka': SeedProtocol.keeloq,
        },
      );
    });

    test('the counter width and the reversal follow the protocol', () {
      // Spelled out rather than computed from the enum, which would restate
      // the values instead of pinning them.
      expect(
        {
          for (final p in SeedProtocol.values)
            p.inFile: (p.counterDigits, p.framesAreBitReversed),
        },
        {'Faac SLH': (5, false), 'KeeLoq': (4, true)},
      );
    });
  });
}
