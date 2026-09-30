import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/emulate/service.dart';

import 'fake_app_client.dart';

/// Whether a press reached the Flipper, as far as whoever asked for it can
/// tell.
///
/// Both of these went out through a queue whose contract is that a failure
/// cannot strand the commands behind it - so the future never rejects, and
/// the caller had no way to tell a transmit that happened from one that did
/// not. The home-screen widget flashed "sent" for both. #104.
void main() {
  late FakeAppClient client;
  late EmulateService service;

  setUp(() {
    client = FakeAppClient();
    service = EmulateService(client: client);
    addTearDown(client.close);
  });

  /// Starts a run, then puts the scene back the way a second hold finds it:
  /// pressed and released once, so the next press has to reload.
  Future<void> startAndCycle() async {
    await service.start(key());
    await service.sendPress();
    await service.sendRelease();
  }

  group('a press the Flipper took', () {
    test('says so', () async {
      await service.start(key());

      expect(await service.sendPress(), isTrue);
      expect(client.calls, contains('appButtonPress'));
    });

    test('and the release after it says so too', () async {
      await service.start(key());
      await service.sendPress();

      expect(await service.sendRelease(), isTrue);
    });

    // The transmitter is already keyed, so the press the caller asked for is
    // in effect - reporting false here would flash a failure over a send that
    // is happening.
    test('is not reported failed when it was already keyed', () async {
      await service.start(key());
      await service.sendPress();

      expect(await service.sendPress(), isTrue);
    });

    // Nothing keyed, nothing to release, nothing failed.
    test('has a release that is not failed when nothing was keyed', () async {
      await service.start(key());

      expect(await service.sendRelease(), isTrue);
    });
  });

  group('a press that never reached the device', () {
    // The ordinary way: a five-second RPC timeout over a link that has gone.
    test('says so rather than ending quietly', () async {
      await service.start(key());
      client.pressThrows = StateError('no response');

      expect(await service.sendPress(), isFalse);
    });

    test('has a release that says so too', () async {
      await service.start(key());
      await service.sendPress();
      client.releaseThrows = StateError('no response');

      expect(await service.sendRelease(), isFalse);
    });

    // The other way in: the scene has to go back on the device before a
    // second hold, and four tries at that can all fail.
    test('says so when the scene would not reload', () async {
      await startAndCycle();
      client.loadThrows = StateError('file missing');

      expect(await service.sendPress(), isFalse);
      expect(
        client.calls.where((c) => c == 'appButtonPress'),
        hasLength(1),
        reason: 'the first hold pressed; this one never got that far',
      );
    });

    // The queue must keep its contract while carrying the answer: a failed
    // command cannot strand the ones behind it.
    test('does not stop the command behind it running', () async {
      await service.start(key());
      client.pressThrows = StateError('no response');
      await service.sendPress();
      client.pressThrows = null;

      expect(await service.sendPress(), isTrue);
    });
  });

  // stop() clears the run while a command may still be queued, and a press
  // that ran anyway would leave the transmitter keyed with no release behind
  // it. Nothing reached the Flipper, so nothing is reported as sent.
  test('a press queued behind a stop is not reported as sent', () async {
    await service.start(key());
    await service.stop();

    expect(await service.sendPress(), isFalse);
  });
}
