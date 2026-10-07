// Naming, writing and then clearing away the recovered remote.
//
// The name used to be generated and never shown, so the only way to get it
// wrong was to change `baseName`. It is now typed by the user, which adds two
// failures that did not exist: a name the storage layer cannot carry, and a
// name that is already somebody else's file. Both guards are in the controller
// rather than the page - the second one especially, because a caller that
// skipped it would destroy a file the user recorded by hand.
//
// The Flipper is `test/seed_fakes.dart`, which explains where it cuts in.
//
// What this cannot see: anything the page does. The two confirm dialogs - and
// so the polarity of "Cancel means do not overwrite" and "Keep It means do not
// delete" - are `test/seed_page_test.dart`.
//
// Nor can it see `deleteCapture` refusing a binding whose link has died. That
// guard matters - the delete would otherwise land on whichever Flipper is
// connected when the confirm is answered - but the shape it tests for cannot
// be built from outside flipperlib: `FlipperSessionBinding.to` is documented
// as always alive and `.unbound()` names no device, so "named and unreachable"
// has no public constructor. Covered by reading, not by running.
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_capture_format.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_controller.dart';

import 'seed_fakes.dart';

void main() {
  group('the name offered', () {
    test('is the generated one, without the extension', () async {
      final controller = await saveableSeedController(SeedFakeClient());
      expect(controller.suggestedName, 'Genius_A0DC9330');
    });

    test('is null when the recovery is not one that can be saved', () async {
      // Not "when there is no capture at all" - that short-circuits on the
      // capture and never exercises the canSave term this getter exists for.
      // The page reads it before opening the dialog.
      final controller = await openedSeedController(
        SeedFakeClient(),
        recoverer: UnverifiedRecoverer(),
      );
      await controller.search();
      expect(controller.canSave, isFalse);
      expect(controller.suggestedName, isNull);
    });
  });

  group('listing the capture folder', () {
    test('is a stage, so the toolbar can show it', () async {
      final controller = SeedController(client: SeedFakeClient());
      expect(controller.stage, SeedStage.idle);
      final inFlight = controller.refresh();
      expect(controller.stage, SeedStage.listing);
      await inFlight;
      expect(controller.stage, SeedStage.idle);
    });

    test('a folder that was never created is simply empty', () async {
      // The one failure that really is "nothing captured yet", and the
      // firmware says so by name rather than through an error string.
      final client = SeedFakeClient()
        ..listThrows = FlipperRpcStorageNotExistException(Main());
      final controller = SeedController(client: client);
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.files, isEmpty);
      expect(controller.stage, SeedStage.idle);
    });

    test('a listing that failed is not reported as an empty folder', () async {
      // The page says "No captures on this Flipper" for an empty list and
      // tells the user to go record one. Saying that because an SD card was
      // busy sends them to re-record a remote they already captured.
      final client = SeedFakeClient()
        ..folder['one.txt'] = seedCaptureFixture
        ..listThrows = StateError('storage busy');
      final controller = SeedController(client: client);
      await controller.refresh();
      expect(controller.error, SeedFailure.listFailed);
      expect(controller.stage, SeedStage.idle);
    });

    test('and leaves the rows already on screen alone', () async {
      // They are still the last thing the device actually said.
      final client = SeedFakeClient()..folder['one.txt'] = seedCaptureFixture;
      final controller = SeedController(client: client);
      await controller.refresh();
      expect(controller.files, hasLength(1));

      client.listThrows = StateError('storage busy');
      await controller.refresh();
      expect(controller.files.map((f) => f.name), ['one.txt']);
    });

    test('a dead link is told apart from a live device that refused', () async {
      final client = SeedFakeClient()
        ..listThrows = StateError('link dropped')
        ..connected = false;
      final controller = SeedController(client: client);
      await controller.refresh();
      expect(controller.error, SeedFailure.disconnected);
    });
  });

  group('save', () {
    test('writes the chosen name, not the suggested one', () async {
      final client = SeedFakeClient();
      final controller = await saveableSeedController(client);
      await controller.save('front gate');

      expect(controller.error, isNull);
      expect(controller.savedTo, '/ext/subghz/front gate.sub');
      expect(client.writes.keys, ['/ext/subghz/front gate.sub']);
      // And it is the real file, so a save that wrote nothing - or wrote a
      // capture rather than a key file - is not read as success.
      expect(
        utf8.decode(client.writes.values.single),
        allOf(
          contains('Filetype: Flipper SubGhz Key File'),
          contains('Seed: 54 6A A4 4F'),
        ),
      );
    });

    test('refuses a name the rules reject, and says which failure', () async {
      // Its own member: "the Flipper refused this" is not true here, and it
      // leaves the user nothing to change.
      //
      // `calls` rather than `error` alone, because a write that was attempted
      // and failed also sets a failure - so the error cannot tell the guard
      // from its absence. A mutation run proved that: before the write pump
      // was faked, this passed with the guard replaced by `if (false)`.
      final client = SeedFakeClient();
      final controller = await saveableSeedController(client);
      client.calls.clear();

      await controller.save('bad/name');

      expect(controller.error, SeedFailure.invalidName);
      expect(controller.savedTo, isNull);
      expect(
        client.calls,
        isEmpty,
        reason: 'nothing should have been sent to the device',
      );
    });

    test('reports a write the device refused', () async {
      // The other half of the pair above: here the write *is* attempted and a
      // failure still has to come back, or the user presses Save, nothing
      // happens, and the button is still there.
      final client = SeedFakeClient()..writeThrows = StateError('card full');
      final controller = await saveableSeedController(client);

      await controller.save('garage');

      expect(controller.error, SeedFailure.saveFailed);
      expect(controller.savedTo, isNull);
      expect(client.calls, contains('write(/ext/subghz/garage.sub)'));
    });

    test('neither writes nor throws for a result canSave refuses', () async {
      // `render` refuses an outcome that is not `found` and dereferences the
      // seed. Before this guard the throw escaped the task and landed in a
      // discarded future as an `[uncaught]` naming no operation, leaving the
      // page exactly as it was.
      final client = SeedFakeClient();
      final controller = await openedSeedController(
        client,
        recoverer: UnverifiedRecoverer(),
      );
      await controller.search();
      expect(
        controller.canSave,
        isFalse,
        reason: 'fixture must not be saveable',
      );
      client.calls.clear();

      await controller.save('garage');

      expect(client.calls, isEmpty);
      expect(controller.savedTo, isNull);
    });

    test(
      'says a save is in flight, so a second press cannot start one',
      () async {
        // savedTo cannot answer this: it is set only once the write has landed,
        // so between the stat and the last frame it is still null.
        final controller = await saveableSeedController(SeedFakeClient());
        expect(controller.saving, isFalse);
        final inFlight = controller.save('garage');
        expect(controller.saving, isTrue);
        await inFlight;
        expect(controller.saving, isFalse);
      },
    );
  });

  group('refusing to clobber', () {
    test('a standing file stops the write and names itself', () async {
      final client = SeedFakeClient()..existing.add('/ext/subghz/garage.sub');
      final controller = await saveableSeedController(client);

      await controller.save('garage');

      expect(controller.error, SeedFailure.nameTaken);
      expect(controller.savedTo, isNull);
      expect(
        client.writes,
        isEmpty,
        reason: 'the standing file must still be the one on the device',
      );
    });

    test('and replace: true is the answer to it', () async {
      final client = SeedFakeClient()..existing.add('/ext/subghz/garage.sub');
      final controller = await saveableSeedController(client);
      await controller.save('garage');

      await controller.save('garage', replace: true);

      expect(controller.error, isNull);
      expect(controller.savedTo, '/ext/subghz/garage.sub');
      expect(client.writes.keys, ['/ext/subghz/garage.sub']);
    });

    test('a free path is not a collision', () async {
      // The firmware refuses the stat rather than answering an empty one, so
      // the ordinary case arrives as an exception. Reading that as "taken"
      // would put a replace prompt in front of every first save.
      final controller = await saveableSeedController(SeedFakeClient());
      await controller.save('garage');
      expect(controller.error, isNull);
      expect(controller.savedTo, isNotNull);
    });

    test('a stat that went unanswered is its own failure', () async {
      // Not "free". The page has to say something different about a file it
      // has not seen than about one it has - and proceeding silently would
      // destroy a `.sub` the user recorded by hand, reported in success
      // colours, with one warn line as the only trace.
      final client = SeedFakeClient()..statThrows = StateError('link busy');
      final controller = await saveableSeedController(client);

      await controller.save('garage');

      expect(controller.error, SeedFailure.nameUnchecked);
      expect(client.writes, isEmpty);
    });

    test('the stat asks about the name it was given', () async {
      final client = SeedFakeClient();
      final controller = await saveableSeedController(client);
      await controller.save('something_else');
      expect(client.calls, contains('stat(/ext/subghz/something_else.sub)'));
    });
  });

  group('deleting the solved capture', () {
    test('is not offered until the remote has been saved', () async {
      final controller = await openedSeedController(SeedFakeClient());
      expect(controller.canDeleteCapture, isFalse);

      await controller.search();
      expect(
        controller.canDeleteCapture,
        isFalse,
        reason: 'a solved capture is not a saved one',
      );

      await controller.save('garage');
      expect(controller.canDeleteCapture, isTrue);
    });

    test('removes the file and drops it from the list', () async {
      final client = SeedFakeClient();
      final controller = await saveableSeedController(client);
      await controller.save('garage');

      await controller.deleteCapture();

      expect(client.calls, contains('delete($seedCaptureDir/one.txt)'));
      expect(client.folder, isEmpty);
      expect(controller.files, isEmpty);
      expect(controller.openedFile, isNull);
      expect(controller.error, isNull);
    });

    test('drops only the row it deleted', () async {
      // The row removal is the only thing that updates the list now - there is
      // no re-listing round trip behind it to cover for a filter that takes
      // out too much.
      final client = SeedFakeClient()
        ..folder['one.txt'] = seedCaptureFixture
        ..folder['two.txt'] = seedCaptureFixture;
      final controller = await openedSeedController(client, open: 'one.txt');
      await controller.search();
      await controller.save('garage');

      await controller.deleteCapture();

      expect(controller.files.map((f) => f.name), ['two.txt']);
    });

    test('does nothing at all when the remote was never saved', () async {
      // The guard, not the caller: this deletes the only copy of a capture the
      // user had to be standing next to a remote to take.
      final client = SeedFakeClient();
      final controller = await openedSeedController(client);
      await controller.search();
      client.calls.clear();

      await controller.deleteCapture();

      expect(client.calls, isEmpty);
      expect(client.folder, contains('one.txt'));
    });

    test('says so when the device refuses, and stays retryable', () async {
      // The remote is already saved, so this is not a lost recovery - but a
      // capture that silently stays in the list looks undeleted for no stated
      // reason, and the offer has to survive so it can be taken again.
      final client = SeedFakeClient()..deleteThrows = StateError('read only');
      final controller = await saveableSeedController(client);
      await controller.save('garage');

      await controller.deleteCapture();

      expect(controller.error, SeedFailure.deleteFailed);
      expect(controller.files.map((f) => f.name), ['one.txt']);
      expect(controller.openedFile, isNotNull);
      expect(controller.canDeleteCapture, isTrue);
    });
  });
}
