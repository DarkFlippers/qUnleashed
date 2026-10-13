// Why the Save button is not offered, and in which order the reasons win.
//
// `canSave` used to be a five-term boolean, and the page explained its absence
// by re-deriving two of those terms - so a `found` answer missing a field said
// nothing at all: the headline "Seed recovered" over an empty card when the
// seed was absent, the seed rows with no button and no reason when the rebuilt
// frame or the hop count was. #294 replaced the bool with the reason; this
// suite is the half of it that does not need a widget tree.
//
// The ordering cases are not decoration. Each refusal names something
// different to do next, so a capture that breaks two rules has to report the
// one whose fix the other would not undo - and swapping two clauses is a
// change nothing else in the repo would notice.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/pages/tools/subghz/seed/faaccrack_recoverer.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_capture_format.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

import 'kept_lines.dart';
import 'seed_fakes.dart';

/// A controller that has searched one capture with [recoverer].
Future<SeedController> _searched(
  String capture, {
  required FaaccrackRecoverer recoverer,
  SeedFakeClient? client,
}) async {
  final flipper = (client ?? SeedFakeClient())..folder['one.txt'] = capture;
  final controller = await openedSeedController(flipper, recoverer: recoverer);
  await controller.search();
  return controller;
}

void main() {
  group('a recovery that can be saved', () {
    test('is blocked by nothing', () async {
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: FoundRecoverer(),
      );

      expect(controller.saveBlock, isNull);
      expect(controller.canSave, isTrue);
    });
  });

  group('each refusal names itself', () {
    test('an outcome that is not found is notFound', () async {
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: UnverifiedRecoverer(),
      );

      expect(controller.saveBlock, SeedSaveBlock.notFound);
      expect(controller.canSave, isFalse);
    });

    test('no search at all is notFound too', () async {
      // Nothing on screen reads this - the result card is not built - but
      // `canSave` is read by `suggestedName` and by `save`, and both have to
      // refuse before a search has run.
      final client = SeedFakeClient()..folder['one.txt'] = seedCaptureFixture;
      final controller = await openedSeedController(client);

      expect(controller.result, isNull, reason: 'fixture must not have run');
      expect(controller.saveBlock, SeedSaveBlock.notFound);
    });

    test('a capture with no frequency is noFrequency', () async {
      final controller = await _searched(
        seedCaptureNoFrequency,
        recoverer: FoundRecoverer(),
      );

      expect(
        controller.capture!.frequencyHz,
        isNull,
        reason: 'fixture must have lost its frequency',
      );
      expect(controller.saveBlock, SeedSaveBlock.noFrequency);
    });

    test('an answer under the confidence line is lowConfidence', () async {
      final controller = await _searched(
        seedCaptureTwoHops,
        recoverer: FoundRecoverer(),
      );

      expect(controller.result!.hopsUsed, lessThan(seedHopsConfident));
      expect(controller.saveBlock, SeedSaveBlock.lowConfidence);
    });
  });

  // The state #294 was filed about: a `found` answer the app cannot write and,
  // before this, said nothing about. It is not a fourth refusal of the Save
  // button - it is an answer this build does not understand, so it never
  // reaches the gate as `found` at all. The headline says "The recovery engine
  // failed" rather than "Seed recovered" over a card with nothing in it.
  group('an answer the engine cannot have given', () {
    for (final (field, recoverer) in [
      ('seed', IncompleteRecoverer(seed: null)),
      // Its own case rather than a variant: `render` dereferences both the
      // seed and the rebuilt frame, so either one missing is the same throw.
      ('rebuilt frame', IncompleteRecoverer(frameHop: null)),
      // And not `lowConfidence`: an answer that does not say how many hops
      // back it cannot be judged, and "backed by only 0 hops" is a figure
      // nothing measured.
      ('hop count', IncompleteRecoverer(hopsUsed: null)),
    ]) {
      test('found without the $field is an engine fault', () async {
        final controller = await _searched(
          seedCaptureFixture,
          recoverer: recoverer,
        );

        expect(controller.result!.outcome, SeedOutcome.engineFault);
        expect(controller.saveBlock, SeedSaveBlock.notFound);
      });
    }

    // The asymmetry in the wholeness check, and the only tests that can see
    // it: the seed is what both outcomes are for, while the rebuilt frame and
    // the hop count are `found`'s promises alone - `render` writes the one and
    // the confidence clause is the only reader of the other, and `notFound`
    // short-circuits that for every outcome but `found`. Demanding either of
    // `unverified` turns an answer that renders perfectly well into "The
    // recovery engine failed" and throws away the seed it was shown for.
    for (final (figure, recoverer) in [
      ('rebuilt frame', UnverifiedRecoverer(frameHop: null)),
      ('hop count', UnverifiedRecoverer(hopsUsed: null)),
    ]) {
      test('does not demand a $figure of an answer that has none', () async {
        final controller = await _searched(
          seedCaptureFixture,
          recoverer: recoverer,
        );

        expect(controller.result!.outcome, SeedOutcome.unverified);
        expect(controller.result!.seed, isNotNull);
      });
    }

    test('does demand both of a found answer', () async {
      // The other side of the asymmetry, so it cannot pass by exempting
      // everything: `found` writes a file out of all three.
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: IncompleteRecoverer(hopsUsed: null),
      );

      expect(controller.result!.outcome, SeedOutcome.engineFault);
    });

    test('keeps a whole answer whole', () async {
      // The other side of it, so the check cannot pass by refusing
      // everything: `unverified` carries its figures too, and is not a fault.
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: UnverifiedRecoverer(),
      );

      expect(controller.result!.outcome, SeedOutcome.unverified);
      expect(controller.result!.seed, isNotNull);
    });

    test(
      'is recorded, since the headline asks the user to report it',
      () async {
        // At a level that survives a release build: a report that arrives
        // with nothing in the log but `[Seed] searching ...` cannot be acted
        // on.
        //
        // Not "once": `LogService` folds a *consecutive* identical body into
        // the one before, so a count here cannot tell once from twice - the
        // trap CLAUDE.md names. This suite builds no widget for a per-rebuild
        // claim to be about either; what holds that is the single call site in
        // `search`'s `finally`, and `seed_save_hint_test.dart` pins it where
        // rebuilds happen.
        recordKeptLines();
        await _searched(
          seedCaptureFixture,
          recoverer: IncompleteRecoverer(hopsUsed: null),
        );

        expect(
          keptLines.where((l) => l.contains('without the whole answer')),
          isNotEmpty,
        );
        expect(keptLevels, contains(KeptLevel.error));
      },
    );

    test('says which field was missing', () async {
      // The field, because the three have different causes - a zeroed
      // `hops_used` from a struct that drifted is not a null seed from a
      // bridge that is not the engine.
      recordKeptLines();
      await _searched(
        seedCaptureFixture,
        recoverer: IncompleteRecoverer(seed: null),
      );

      final line = keptLines.singleWhere(
        (l) => l.contains('without the whole answer'),
      );
      expect(line, contains('seed=false'));
      // And which sweep it came out of: `search` tries up to three windows and
      // only the last answer survives, so the same gap out of a whole-capture
      // sweep and out of a three-hop retry are different faults.
      expect(line, contains('3-hop window'));
    });

    test('is not recorded for an answer that is merely unconfident', () async {
      // A two-hop capture is the user's own data and nothing is wrong with it.
      recordKeptLines();
      await _searched(seedCaptureTwoHops, recoverer: FoundRecoverer());

      expect(
        keptLines.where((l) => l.contains('without the whole answer')),
        isEmpty,
      );
    });
  });

  group('two refusals at once report', () {
    test('notFound, which subsumes every clause under it', () async {
      // The card's own headline already reads as a refusal for an outcome
      // that is not `found`; a second sentence about the hop count would
      // misattribute it, which is what the page used to do.
      final controller = await _searched(
        seedCaptureTwoHops,
        recoverer: UnverifiedRecoverer(hopsUsed: 2),
      );

      // The state that makes this case worth having, and the one a fake
      // answering with every field null could not build: a seed on screen,
      // backed by too few hops, refused for a reason that is not the hops.
      expect(controller.result!.seed, isNotNull);
      expect(controller.result!.hopsUsed, lessThan(seedHopsConfident));
      expect(controller.saveBlock, SeedSaveBlock.notFound);
    });

    test(
      'notFound for a malformed answer, whatever the capture holds',
      () async {
        // A fault in the build outranks everything about the capture, and it
        // does so by never arriving as `found`: the frequency and the hop count
        // are both wrong here too, and neither is what the user is told.
        final controller = await _searched(
          withoutFrequency(seedCaptureTwoHops),
          recoverer: IncompleteRecoverer(seed: null, hopsUsed: 2),
        );

        expect(controller.capture!.frequencyHz, isNull);
        expect(controller.result!.outcome, SeedOutcome.engineFault);
        expect(controller.saveBlock, SeedSaveBlock.notFound);
      },
    );

    test('notFound before noFrequency', () async {
      final controller = await _searched(
        seedCaptureNoFrequency,
        recoverer: UnverifiedRecoverer(),
      );

      expect(controller.capture!.frequencyHz, isNull);
      expect(controller.saveBlock, SeedSaveBlock.notFound);
    });

    test('noFrequency before lowConfidence', () async {
      // The hop count is the one another press or two answers - and a user
      // sent off to capture more presses into a file that records no frequency
      // arrives back at the same refusal.
      final controller = await _searched(
        withoutFrequency(seedCaptureTwoHops),
        recoverer: FoundRecoverer(),
      );

      expect(controller.result!.hopsUsed, lessThan(seedHopsConfident));
      expect(controller.capture!.frequencyHz, isNull);
      expect(controller.saveBlock, SeedSaveBlock.noFrequency);
    });
  });

  test('judges the capture it was handed, not the one before it', () async {
    // `debugSetCapture` is the test-only door into the search, and it used to
    // leave the previous result standing - so a suite that searched one capture
    // and swapped in another had `saveBlock` judging the old answer against the
    // new capture's frequency. The gate is only as honest as the state behind
    // it, and this is the shape CLAUDE.md names: a test that passes for a
    // reason other than the one it claims.
    final controller = await _searched(
      seedCaptureFixture,
      recoverer: FoundRecoverer(),
    );
    expect(controller.saveBlock, isNull, reason: 'fixture must be saveable');

    controller.debugSetCapture(
      SeedCaptureFormat.parse(seedCaptureNoFrequency).capture!,
    );

    expect(controller.result, isNull);
    expect(controller.saveBlock, SeedSaveBlock.notFound);
  });

  group('the gate the rest of the controller reads', () {
    test('refuses to name a file for a blocked recovery', () async {
      final controller = await _searched(
        seedCaptureNoFrequency,
        recoverer: FoundRecoverer(),
      );

      expect(controller.suggestedName, isNull);
    });

    test('writes nothing for a blocked recovery', () async {
      // The gate, not `render`: here the outcome *is* `found` and only the
      // frequency is missing, which `_save` passes to `render` with a `!`. Not
      // reaching the write at all is what keeps that out of the log as a
      // failure the device is blamed for.
      recordKeptLines();
      final client = SeedFakeClient();
      final controller = await _searched(
        seedCaptureNoFrequency,
        recoverer: FoundRecoverer(),
        client: client,
      );
      expect(controller.saveBlock, SeedSaveBlock.noFrequency);
      client.calls.clear();
      // The fold as well as the list: `clearKeptLines` resets both, and the
      // arrangement above logs. Without it a body the search already wrote
      // could be folded away out of the act and read as missing wiring.
      clearKeptLines();

      await controller.save('garage');

      expect(client.calls, isEmpty);
      expect(controller.savedTo, isNull);
      // The user is told, and so is the log. Nothing else on this path moves
      // the screen - the button is still there and `savedTo` is still null -
      // so without the failure the app simply does not answer a tap, and
      // without the line nobody can tell which gate turned it away.
      expect(controller.error, SeedFailure.saveFailed);
      expect(
        keptLines.singleWhere((l) => l.contains('[Seed] save refused')),
        contains('noFrequency'),
      );
    });
  });
}
