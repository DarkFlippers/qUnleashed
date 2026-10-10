import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/emulate/service.dart';

import 'kept_lines.dart';

import 'fake_app_client.dart';

/// What an emulation writes down when it does not happen.
///
/// `EmulateResult.fail` is the surface, and it carries a category rather than
/// a cause: the page renders "could not open the app" for a firmware that
/// refused, a link that went and a file that is not there alike. The cause
/// existed only at a level a release build drops, so a bug report about an
/// emulation that would not start arrived with nothing in it. #103, ADR 0008.
void main() {
  setUp(recordKeptLines);

  late FakeAppClient client;
  late EmulateService service;

  setUp(() {
    client = FakeAppClient();
    service = EmulateService(client: client);
    clearKeptLines();
    addTearDown(client.close);
  });

  Iterable<String> lines(String fragment) =>
      keptLines.where((l) => l.contains(fragment));

  group('a run the user is told failed', () {
    test('says why the app would not start', () async {
      client.startThrows = StateError('no such application');

      final result = await service.start(key());

      expect(result.error, EmulateError.appStartFailed);
      expect(lines('no such application'), hasLength(1));
    });

    test('says why the file would not load', () async {
      client.loadThrows = StateError('file missing');

      final result = await service.start(key());

      expect(result.error, EmulateError.loadFileFailed);
      expect(lines('file missing'), hasLength(1));
    });

    // The other entry point: an app opened for the user to drive themselves,
    // which fails into the same category.
    test('says why an app launch would not start', () async {
      client.startThrows = StateError('no such application');

      final result = await service.launchApp(key());

      expect(result.error, EmulateError.appStartFailed);
      expect(lines('no such application'), hasLength(1));
    });

    // Busy is a "try again", not a failure, and the exception type is the
    // whole answer - there is nothing a log line could add.
    test('says nothing extra when the device is merely busy', () async {
      client.startThrows = FlipperRpcBusyException(Main());

      final result = await service.start(key());

      expect(result.error, EmulateError.busy);
      expect(lines('[Emulate]'), isEmpty);
    });
  });

  // Nothing treats this as a failure: a null protocol resolves to a different
  // launch method, so the button quietly does something other than what the
  // file asks for.
  group('a protocol that could not be read', () {
    test('is reported, though the caller is handed a null', () async {
      client.readThrows = StateError('card gone');

      expect(await service.fetchProtocol(key()), isNull);
      expect(lines('could not read the protocol'), hasLength(1));
    });

    test('says nothing when the file reads', () async {
      client.fileBody = 'Filetype: Flipper SubGhz Key File\nProtocol: RAW\n';

      expect(await service.fetchProtocol(key()), isNotNull);
      expect(lines('[Emulate]'), isEmpty);
    });
  });

  group('a scene that will not load before a press', () {
    // Four tries in under a second, so the per-attempt lines are info. This
    // is the tally at the end of them, and the press that follows is never
    // sent - with nothing on screen saying so (#104).
    test('is reported once the run gives up, not once per try', () async {
      await service.start(key());
      await service.sendPress();
      await service.sendRelease();
      client.loadThrows = StateError('file missing');
      clearKeptLines();

      await service.sendPress();

      expect(lines('gave up reloading'), hasLength(1));
      // The four tries either side of it are info and stay there. Promoting
      // them would put five lines up for one press the user cannot even see
      // failed, which is the opposite of what the tally is for.
      expect(lines('[Emulate]'), hasLength(1));
    });

    test('names the file that would not go back on', () async {
      await service.start(key());
      await service.sendPress();
      await service.sendRelease();
      client.loadThrows = StateError('file missing');
      clearKeptLines();

      await service.sendPress();

      expect(lines('/ext/subghz/garage.sub'), isNotEmpty);
    });

    test('says nothing when the scene goes back on', () async {
      await service.start(key());
      await service.sendPress();
      await service.sendRelease();
      clearKeptLines();

      await service.sendPress();

      expect(lines('gave up reloading'), isEmpty);
      expect(client.calls, contains('appButtonPress'));
    });
  });

  group('an app left running on the Flipper', () {
    // The next emulate the user starts comes back "device busy", which is a
    // symptom one step removed from its cause.
    test('is reported when the exit is refused', () async {
      await service.start(key());
      client.exitThrows = StateError('no response');
      clearKeptLines();

      await service.stop();

      expect(lines('appExit failed'), hasLength(1));
    });

    test('says nothing when the exit goes through', () async {
      await service.start(key());
      clearKeptLines();

      await service.stop();

      expect(lines('[Emulate]'), isEmpty);
    });
  });
}
