// Why the Save button is not offered, and in which order the reasons win.
//
// `canSave` used to be a four-term boolean, and the page explained its absence
// by re-deriving two of those four terms - so a `found` answer with a field
// missing, or one that did not say how many hops backed it, showed the seed
// rows, no button and no sentence anywhere. #294 replaced the bool with the
// reason; this suite is the half of it that does not need a widget tree.
//
// The ordering cases are not decoration. Each refusal names something
// different to do next, so a capture that breaks two rules has to report the
// one whose fix the other would not undo - and swapping two clauses is a
// change nothing else in the repo would notice.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/faaccrack_recoverer.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_models.dart';

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
      // dereferences both, and a guard that covered only the seed is what the
      // comment on the old boolean was there to prevent.
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
      // The card's own headline and hint already explain an outcome that is
      // not `found`; a second sentence about the hop count would misattribute
      // the refusal, which is what the page used to do.
      final controller = await _searched(
        seedCaptureTwoHops,
        recoverer: UnverifiedRecoverer(),
      );

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

  group('the gate the rest of the controller reads', () {
    test('refuses to name a file for a blocked recovery', () async {
      final controller = await _searched(
        seedCaptureNoFrequency,
        recoverer: FoundRecoverer(),
      );

      expect(controller.suggestedName, isNull);
    });

    test('writes nothing for a blocked recovery', () async {
      // `render` refuses an outcome that is not `found` and dereferences the
      // seed, so this is the guard that keeps the throw out of a discarded
      // future. Here the outcome *is* `found` - only the frequency is missing,
      // which `render` would dereference with `!`.
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
