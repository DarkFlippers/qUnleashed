import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Waiting for a Flipper to come back, and remembering whether one is there.
///
/// Two things `LinkService` does that nothing else can: it holds the wait that
/// a firmware install runs inside, and it decides whether a remembered BLE
/// device shows as within reach. Both had no tests.
///
/// `awaitUsbReturn` is the one with teeth. A firmware install sends the
/// Flipper away and the app has to know when it is back — not that *a* Flipper
/// is back, and not that this one is still here.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id, this.transport);

  @override
  final String id;

  @override
  String get name => id;

  @override
  final DeviceTransport transport;
}

FlipperDevice usb(String id) => FlipperDevice(
  id: id,
  name: id,
  link: FlipperLink.usb,
  source: _Discovered(id, DeviceTransport.usb),
);

FlipperDevice ble(String id) => FlipperDevice(
  id: id,
  name: id,
  link: FlipperLink.ble,
  source: _Discovered(id, DeviceTransport.ble),
);

FlipperSessionInfo up(FlipperDevice device) => FlipperSessionInfo(
  device: device,
  connected: true,
  connecting: false,
  active: true,
);

/// A link going down for [device], with [closeReason] set unless it is a
/// reconnect or a still-running attempt.
FlipperConnectionState dropped(
  FlipperDevice device, {
  bool reconnecting = false,
  bool connecting = false,
  Object? closeReason = 'link fault',
}) => FlipperConnectionState(
  mode: FlipperMode.disconnected,
  device: device,
  connected: false,
  closeReason: closeReason,
  reconnecting: reconnecting,
  connecting: connecting,
);

class FakeReturnClient implements FlipperClient {
  final _usbEvents = StreamController<void>.broadcast();
  final _sessions = StreamController<List<FlipperSessionInfo>>.broadcast();
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _heard = StreamController<FlipperDevice>.broadcast();

  @override
  List<FlipperSessionInfo> sessions = const [];

  Future<void> close() async {
    await _usbEvents.close();
    await _sessions.close();
    await _connection.close();
    await _heard.close();
  }

  void plugged() => _usbEvents.add(null);

  void reportSessions(List<FlipperSessionInfo> now) {
    sessions = now;
    _sessions.add(now);
  }

  void reportLink(FlipperConnectionState state) => _connection.add(state);

  void reportHeard(FlipperDevice device) => _heard.add(device);

  int _watchers = 0;

  /// How many subscriptions are open on the session stream.
  ///
  /// Counted rather than read off `hasListener`, which cannot see past the
  /// first: `LinkService.start` holds one for the service's whole life, so a
  /// wait that never let go would look exactly like one that did.
  int get sessionWatchers => _watchers;

  @override
  Stream<void> get usbEvents => _usbEvents.stream;

  @override
  Stream<List<FlipperSessionInfo>> get sessionsStream {
    StreamSubscription<List<FlipperSessionInfo>>? inner;
    late final StreamController<List<FlipperSessionInfo>> out;
    out = StreamController<List<FlipperSessionInfo>>(
      onListen: () {
        _watchers++;
        inner = _sessions.stream.listen(out.add, onError: out.addError);
      },
      onCancel: () async {
        _watchers--;
        await inner?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<FlipperDevice> get bleHeard => _heard.stream;

  @override
  List<FlipperDevice> get devices => const [];

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => sessions.any((s) => s.connected);

  @override
  FlipperDevice? get connectedDevice =>
      sessions.where((s) => s.connected).map((s) => s.device).firstOrNull;

  @override
  FlipperDevice? get connectingDevice => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> disconnectDevice(String id, {FlipperLink? link}) async {}

  @override
  bool isFlipperDevice(FlipperDevice device) => true;

  @override
  String? getNameOf(FlipperDevice device) => null;

  @override
  Future<List<FlipperDevice>> refreshUsbOnly() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeReturnClient client;
  late LinkService links;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final settings = DeviceSettings.instance..reset();
    await settings.load();
    await settings.setAutoConnectUsb(false);
    await settings.setAutoConnectBle(false);

    final known = KnownDevicesStore.instance;
    await known.load();
    for (final device in [...known.devices]) {
      await known.forget(device);
    }

    client = FakeReturnClient();
    links = LinkService.forTest(client);
    addTearDown(() async {
      links.dispose();
      await client.close();
    });
  });

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

  group('waiting for a Flipper to come back', () {
    // The device is still on the bus when the wait starts, which is the real
    // case: the install begins before the reboot. Completing here would end
    // the wait before anything had happened.
    test('does not end on the link it already had', () async {
      client.sessions = [up(usb('A'))];
      var done = false;
      unawaited(links.awaitUsbReturn(usb('A')).then((_) => done = true));
      await tick();

      client.reportSessions([up(usb('A'))]);
      await tick();

      expect(done, isFalse);
    });

    test('ends once it has gone and returned', () async {
      client.sessions = [up(usb('A'))];
      var done = false;
      unawaited(links.awaitUsbReturn(usb('A')).then((_) => done = true));
      await tick();

      client.reportSessions(const []);
      await tick();
      expect(done, isFalse, reason: 'gone is only half of it');

      client.reportSessions([up(usb('A'))]);
      await tick();

      expect(done, isTrue);
    });

    // Already gone when the wait starts: an install that got as far as the
    // reboot before anyone asked.
    test('ends on the first return when it was already away', () async {
      client.sessions = const [];
      var done = false;
      unawaited(links.awaitUsbReturn(usb('A')).then((_) => done = true));
      await tick();

      client.reportSessions([up(usb('A'))]);
      await tick();

      expect(done, isTrue);
    });

    // This device, not whichever Flipper turns up. The link belongs to the one
    // that was sent away to install.
    test('is not ended by a different Flipper arriving', () async {
      client.sessions = const [];
      var done = false;
      unawaited(links.awaitUsbReturn(usb('A')).then((_) => done = true));
      await tick();

      client.reportSessions([up(usb('B'))]);
      await tick();

      expect(done, isFalse);
    });

    test('is not ended by the same Flipper over BLE', () async {
      client.sessions = const [];
      var done = false;
      unawaited(links.awaitUsbReturn(usb('A')).then((_) => done = true));
      await tick();

      client.reportSessions([up(ble('A'))]);
      await tick();

      expect(done, isFalse, reason: 'the install is on the cable');
    });

    // A firmware install can run for half an hour and the wait has no
    // deadline, so a subscription left behind is one per install for the life
    // of the process.
    test('lets go of the stream once it is over', () async {
      final before = client.sessionWatchers;
      client.sessions = const [];
      final wait = links.awaitUsbReturn(usb('A'));
      await tick();
      expect(
        client.sessionWatchers,
        before + 1,
        reason: 'the wait is watching',
      );

      client.reportSessions([up(usb('A'))]);
      await wait;

      expect(client.sessionWatchers, before);
    });
  });

  group('whether a remembered Flipper is within reach', () {
    setUp(() => KnownDevicesStore.instance.remember(ble('B1')));

    bool heardOf(String id) =>
        links.entries.firstWhere((e) => e.id == id).heard;

    test('starts as no', () async {
      client.plugged();
      await tick();

      expect(heardOf('B1'), isFalse);
    });

    test('becomes yes when the radio hears it', () async {
      client.reportHeard(ble('B1'));
      await tick();

      expect(heardOf('B1'), isTrue);
    });

    // Heard before it was remembered is not evidence it is here now. The
    // check has to be at the moment of hearing, and asserting only that a
    // stranger grows no row misses that entirely - a stranger has no row
    // either way.
    test('is not claimed from before it was remembered', () async {
      client.reportHeard(ble('stranger'));
      await tick();

      await KnownDevicesStore.instance.remember(ble('stranger'));
      client.plugged();
      await tick();

      expect(heardOf('stranger'), isFalse);
      expect(links.entries.map((e) => e.id), contains('stranger'));
    });

    test('becomes yes when a link comes up', () async {
      client.reportLink(
        const FlipperConnectionState(
          mode: FlipperMode.rpc,
          device: null,
          connected: true,
        ).let(ble('B1')),
      );
      await tick();

      expect(heardOf('B1'), isTrue);
    });

    test('goes back to no when the link fails', () async {
      client.reportHeard(ble('B1'));
      await tick();

      client.reportLink(dropped(ble('B1')));
      await tick();

      expect(heardOf('B1'), isFalse);
    });

    // An automatic reconnect is the client saying it has this: the device has
    // not gone anywhere, and dimming the row would be a lie that corrects
    // itself a second later.
    test('stays yes while the client is reconnecting', () async {
      client.reportHeard(ble('B1'));
      await tick();

      // With a reason, because a drop that carries none is already ignored by
      // the next condition along - this case passed without reading
      // `reconnecting` at all until a mutation said so.
      client.reportLink(dropped(ble('B1'), reconnecting: true));
      await tick();

      expect(heardOf('B1'), isTrue);
    });

    // The user closing a link says nothing about whether the Flipper is
    // there, and the row should not go dim because they pressed disconnect.
    test('stays yes when the user closed the link', () async {
      client.reportHeard(ble('B1'));
      await tick();
      await links.disconnectDevice(ble('B1'), id: 'B1', link: FlipperLink.ble);

      client.reportLink(dropped(ble('B1')));
      await tick();

      expect(heardOf('B1'), isTrue);
    });
  });
}

extension on FlipperConnectionState {
  /// The same state, about [device]. `FlipperConnectionState` takes its device
  /// in the constructor and a const one cannot name a non-const value.
  FlipperConnectionState let(FlipperDevice device) => FlipperConnectionState(
    mode: mode,
    device: device,
    connected: connected,
    closeReason: closeReason,
    reconnecting: reconnecting,
    connecting: connecting,
  );
}
