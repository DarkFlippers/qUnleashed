import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/emulate/service.dart';

import 'fake_app_client.dart';

/// Opening a key on the Flipper, and every way that goes wrong.
///
/// This is the half of `EmulateService` that `emulate_service_test.dart` said
/// it could not reach: `start` binds the session first, and
/// `FlipperSessionBinding`'s only constructor was private to flipperlib, so a
/// fake client could not return one. `FlipperSessionBinding.unbound()` is what
/// opened it — dart-flipperlib#5.
///
/// What is still not covered is the reason the binding exists: an emulation
/// belongs to the Flipper it started on, and `_onConnection` closes it when
/// another takes its place. That needs a *live* session, which `unbound` is
/// by definition not.
void main() {
  late FakeAppClient client;
  late EmulateService service;

  setUp(() {
    client = FakeAppClient();
    service = EmulateService(client: client);
  });
  tearDown(() => client.close());

  group('a run that works', () {
    test('starts the app and loads the file, in that order', () async {
      final result = await service.start(key());

      expect(result.isOk, isTrue);
      expect(client.calls, [
        'appStart(Sub-GHz, RPC)',
        'appLoadFile(/ext/subghz/garage.sub)',
      ]);
    });

    test('is running, and remembers what on', () async {
      await service.start(key());

      expect(service.isRunning, isTrue);
      expect(service.activeKey?.name, 'garage');
    });

    // The app is started with `RPC` as its argument, not the file: the file
    // arrives separately through appLoadFile, and an app handed a path as an
    // argument opens it without the app ever entering RPC mode.
    test('starts the app in RPC mode rather than with the file', () async {
      await service.start(key());

      expect(client.calls.first, contains('RPC'));
      expect(client.calls.first, isNot(contains('/ext/')));
    });
  });

  group('the app refusing to start', () {
    test('reads a locked system as busy, not as a failure', () async {
      client.startThrows = rpcFailure(FlipperRpcAppSystemLockedException.new);

      final result = await service.start(key());

      expect(result.error, EmulateError.busy);
    });

    test('reads a busy device as busy', () async {
      client.startThrows = rpcFailure(FlipperRpcBusyException.new);

      final result = await service.start(key());

      expect(result.error, EmulateError.busy);
    });

    // Busy is a "try again"; anything else is not, and the two show the user
    // different things.
    test('reads anything else as a failed start', () async {
      client.startThrows = StateError('transport is gone');

      final result = await service.start(key());

      expect(result.error, EmulateError.appStartFailed);
    });

    test('never reaches the file', () async {
      client.startThrows = StateError('transport is gone');

      await service.start(key());

      expect(client.calls, ['appStart(Sub-GHz, RPC)']);
      expect(service.isRunning, isFalse);
    });
  });

  group('the file refusing to load', () {
    setUp(() => client.loadThrows = StateError('no such file'));

    test('is its own answer, not a failed start', () async {
      final result = await service.start(key());

      expect(result.error, EmulateError.loadFileFailed);
    });

    // The app is already up at this point. Leaving it there would strand a
    // scene on the Flipper with nothing driving it.
    test('closes the app it had already started', () async {
      await service.start(key());

      expect(client.calls, contains('appExit'));
      expect(service.isRunning, isFalse);
      expect(service.activeKey, isNull);
    });
  });

  // The real device does not always send APP_STARTED, so the call waits and
  // then goes on anyway. Without the fallback the load would never be tried.
  test('loads the file even when the app never says it started', () async {
    client.reportsStarted = false;

    final result = await service
        .start(key())
        .timeout(const Duration(seconds: 30));

    expect(result.isOk, isTrue);
    expect(client.calls, contains('appLoadFile(/ext/subghz/garage.sub)'));
  });

  test('a second start closes the first', () async {
    await service.start(key());
    client.calls.clear();

    await service.start(key());

    expect(
      client.calls.first,
      'appExit',
      reason: 'the run still open belongs to the Flipper it started on',
    );
  });
}
