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
}) async {
  final client = SeedFakeClient()..folder['one.txt'] = capture;
  final controller = await openedSeedController(client, recoverer: recoverer);
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

    test('found without a seed is incompleteAnswer', () async {
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: IncompleteRecoverer(seed: null),
      );

      expect(controller.saveBlock, SeedSaveBlock.incompleteAnswer);
    });

    test('found without the rebuilt frame is incompleteAnswer', () async {
      // Its own case rather than a variant of the one above: `render`
      // dereferences both, so either one missing is a throw at the same call.
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: IncompleteRecoverer(frameHop: null),
      );

      expect(controller.saveBlock, SeedSaveBlock.incompleteAnswer);
    });

    test('found without a hop count is incompleteAnswer', () async {
      // Not lowConfidence. An answer that does not say how many hops back it
      // cannot be judged at all, and "backed by only 0 hops" is a figure
      // nothing measured.
      final controller = await _searched(
        seedCaptureFixture,
        recoverer: IncompleteRecoverer(hopsUsed: null),
      );

      expect(controller.saveBlock, SeedSaveBlock.incompleteAnswer);
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

  group('two refusals at once report', () {
    test('notFound, which subsumes every clause under it', () async {
      // The card's own headline already reads as a refusal for an outcome
      // that is not `found`; a second sentence about the hop count would
      // misattribute it, which is what the page used to do.
      final controller = await _searched(
        seedCaptureTwoHops,
        recoverer: UnverifiedRecoverer(),
      );

      // The state that makes this case worth having, and the one a fake
      // answering with every field null could not build: a seed on screen,
      // backed by too few hops, refused for a reason that is not the hops.
      expect(controller.result!.seed, isNotNull);
      expect(controller.result!.hopsUsed, lessThan(seedHopsConfident));
      expect(controller.saveBlock, SeedSaveBlock.notFound);
    });

    test('incompleteAnswer before anything about the capture', () async {
      // A fault in the build, so nothing the user does to the capture is the
      // thing to say first.
      final controller = await _searched(
        seedCaptureNoFrequency,
        recoverer: IncompleteRecoverer(seed: null),
      );

      expect(controller.saveBlock, SeedSaveBlock.incompleteAnswer);
    });

    test('incompleteAnswer before lowConfidence', () async {
      // The pair the first version of this suite had only in its degenerate
      // form: `IncompleteRecoverer` defaults to three hops, so every incomplete
      // case sat at the confidence line and the two clauses were never both
      // true. Hoisting the hop-count check above the field check would report a
      // build fault as "Capture another press or two and try again" - the same
      // misdirection #294 is about, one member along.
      final controller = await _searched(
        seedCaptureTwoHops,
        recoverer: IncompleteRecoverer(seed: null, hopsUsed: 2),
      );

      expect(controller.result!.hopsUsed, lessThan(seedHopsConfident));
      expect(controller.saveBlock, SeedSaveBlock.incompleteAnswer);
    });

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
        seedCaptureTwoHops.replaceFirst('Frequency: 433920000\n', ''),
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

  group('an answer the engine cannot have given', () {
    test(
      'is recorded, since its sentence asks the user to report it',
      () async {
        // At a level that survives a release build: the user is told this build
        // is at fault, and a report that arrives with nothing in the log but
        // `[Seed] searching ...` cannot be acted on. Once per result, not once
        // per rebuild - `saveBlock` is read by `build`.
        recordKeptLines();
        await _searched(
          seedCaptureFixture,
          recoverer: IncompleteRecoverer(hopsUsed: null),
        );

        expect(
          keptLines.where((l) => l.contains('without the whole answer')),
          hasLength(1),
        );
        expect(keptLevels, contains(KeptLevel.error));
      },
    );

    test('says which field was missing', () async {
      // The field, because the three have different causes - a zeroed
      // `hops_used` from an ABI mismatch is not the same fault as a null seed.
      recordKeptLines();
      await _searched(
        seedCaptureFixture,
        recoverer: IncompleteRecoverer(seed: null),
      );

      expect(
        keptLines.singleWhere((l) => l.contains('without the whole answer')),
        contains('seed=false'),
      );
    });

    test('is not recorded for an answer that is merely unconfident', () async {
      // The log line belongs to the one state the engine cannot produce. A
      // two-hop capture is the user's own data and nothing is wrong with it.
      recordKeptLines();
      await _searched(seedCaptureTwoHops, recoverer: FoundRecoverer());

      expect(
        keptLines.where((l) => l.contains('without the whole answer')),
        isEmpty,
      );
    });
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
      final client = SeedFakeClient()
        ..folder['one.txt'] = seedCaptureNoFrequency;
      final controller = await openedSeedController(client);
      await controller.search();
      expect(controller.saveBlock, SeedSaveBlock.noFrequency);
      client.calls.clear();

      await controller.save('garage');

      expect(client.calls, isEmpty);
      expect(controller.savedTo, isNull);
    });
  });
}
