import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/services/emulate/service.dart';

/// What `EmulateService` does before it touches the device — ADR 0002.
///
/// It had no test, because it built its own client from `FlipperOneClient()`
/// and there was nothing to hand it. The client is required now, from the
/// emulate page or from the home-screen widget, and these are the cases that
/// reach for it and stop.
///
/// The rest of `start` is not covered here and cannot be cheaply:
/// `bindCurrentSession()` returns a `FlipperSessionBinding`, whose only
/// constructor is private to flipperlib, so a fake cannot produce one. That
/// binding is the mechanism the class is most careful about - an emulation
/// belongs to the Flipper it was started on, across a device switch - and it
/// wants a seam in flipperlib before it can be tested here.
class _NoLink implements FlipperClient {
  bool connected = false;

  /// Anything past the first guard would reach [noSuchMethod] and throw,
  /// which is the point: these cases assert that it never gets that far.
  @override
  bool get isConnected => connected;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ArchiveKey _key() => ArchiveKey(
  name: 'garage',
  category: ArchiveCategory.subghz,
  state: ArchiveKeyState.synced,
  extension: '.sub',
  remotePath: '/ext/subghz/garage.sub',
);

void main() {
  late _NoLink client;
  late EmulateService service;

  setUp(() {
    client = _NoLink();
    service = EmulateService(client: client);
  });

  group('with no link', () {
    test('start says so instead of reaching the device', () async {
      final result = await service.start(_key());

      expect(result.isOk, isFalse);
      expect(result.error, EmulateError.notConnected);
    });

    test('launchApp says so too', () async {
      final result = await service.launchApp(_key());

      expect(result.error, EmulateError.notConnected);
    });

    test('nothing is left running', () async {
      await service.start(_key());

      expect(service.isRunning, isFalse);
      expect(service.activeKey, isNull);
    });
  });

  // The guard reads the client handed in, not a global one. With the old
  // fallback there was no way to tell the two apart from a test at all.
  test('the link it consults is the one it was given', () async {
    expect(
      (await service.start(_key())).error,
      EmulateError.notConnected,
      reason: 'the starting point',
    );

    client.connected = true;

    // Past the guard now, so it reaches `bindCurrentSession` and the fake
    // refuses. Which call it is does not matter; that it got past does.
    await expectLater(service.start(_key()), throwsNoSuchMethodError);
  });

  test('stopping something that never started is quiet', () async {
    await expectLater(service.stop(), completes);
  });
}
