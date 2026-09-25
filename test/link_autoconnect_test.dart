import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When the app dials a Flipper nobody asked it to.
///
/// This is the other half of `_reconcile` from `link_entries_test.dart`: what
/// the service does on its own rather than what it shows. Five pieces of state
/// decide it between them — whether a link is being *held*, whether the user
/// let one go, whether this device has already been tried, whether BLE has
/// been tried at all, and the two settings — and none of it was tested.
///
/// The rule the code states, and the one worth keeping: a Flipper the app is
/// holding comes back whatever the setting says, because the user asked for
/// that link and never let it go. The setting only decides whether the app
/// forms that intent by itself when a cable appears.
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

FlipperSessionInfo connected(FlipperDevice device) => FlipperSessionInfo(
  device: device,
  connected: true,
  connecting: false,
  active: true,
);

class FakeDialClient implements FlipperClient {
  final _usbEvents = StreamController<void>.broadcast();
  final _sessions = StreamController<List<FlipperSessionInfo>>.broadcast();
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _heard = StreamController<FlipperDevice>.broadcast();

  List<FlipperDevice> present = const [];

  @override
  List<FlipperSessionInfo> sessions = const [];

  /// Every dial attempt, in order, as `usb:id` or `ble:id`.
  final dialled = <String>[];

  /// Raised by the next `connect`, so a failed attempt can be watched.
  Object? connectThrows;

  Future<void> close() async {
    await _usbEvents.close();
    await _sessions.close();
    await _connection.close();
    await _heard.close();
  }

  void plugged() => _usbEvents.add(null);

  /// Reports the sessions the client now holds, which is also what tells the
  /// service a USB link is one the app is holding.
  void reportSessions(List<FlipperSessionInfo> now) {
    sessions = now;
    _sessions.add(now);
  }

  @override
  Stream<void> get usbEvents => _usbEvents.stream;

  @override
  Stream<List<FlipperSessionInfo>> get sessionsStream => _sessions.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<FlipperDevice> get bleHeard => _heard.stream;

  @override
  List<FlipperDevice> get devices => present;

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
  bool isFlipperDevice(FlipperDevice device) => true;

  @override
  String? getNameOf(FlipperDevice device) => null;

  @override
  Future<List<FlipperDevice>> refreshUsbOnly() async => present;

  @override
  Future<FlipperDevice> connect(FlipperDevice device) async {
    dialled.add('usb:${device.id}');
    if (connectThrows != null) throw connectThrows!;
    return device;
  }

  @override
  Future<FlipperDevice> connectBleAddress(
    String address, {
    String? name,
    Duration timeout = FlipperClient.bleAddressConnectTimeout,
  }) async {
    dialled.add('ble:$address');
    if (connectThrows != null) throw connectThrows!;
    return ble(address);
  }

  @override
  Future<void> switchToRpcMode() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> disconnectDevice(String id, {FlipperLink? link}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDialClient client;
  late LinkService links;

  /// Builds a service with [usbAuto] and [bleAuto] in force.
  ///
  /// `DeviceSettings` is a singleton that caches its load, so setting the
  /// preference values alone does nothing after the first case has read them -
  /// hence [DeviceSettings.reset] and then its own setters. `resetFirmwareState`
  /// has the same shape for the same reason, and ADR 0002 is about the day
  /// this stops being necessary.
  Future<LinkService> serviceWith({
    bool usbAuto = false,
    bool bleAuto = false,
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    final settings = DeviceSettings.instance..reset();
    await settings.load();
    await settings.setAutoConnectUsb(usbAuto);
    await settings.setAutoConnectBle(bleAuto);

    final known = KnownDevicesStore.instance;
    await known.load();
    for (final device in [...known.devices]) {
      await known.forget(device);
    }
    final service = LinkService.forTest(client);
    addTearDown(service.dispose);
    return service;
  }

  setUp(() {
    client = FakeDialClient();
    addTearDown(() async => client.close());
  });

  /// Lets the debounce and the reconcile behind it run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  group('a cable nobody asked about', () {
    test('is not dialled while the setting is off', () async {
      links = await serviceWith(usbAuto: false);
      client.present = [usb('A')];

      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });

    test('is dialled once while the setting is on', () async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];

      client.plugged();
      await settle();

      expect(client.dialled, ['usb:A']);
    });

    // One attempt per appearance. A Flipper that refuses the link would
    // otherwise be retried on every reconcile, and a reconcile is scheduled
    // by the events a failed connect itself produces.
    test('is not dialled again after a failure', () async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.connectThrows = StateError('port busy');

      client.plugged();
      await settle();
      client.plugged();
      await settle();

      expect(client.dialled, ['usb:A']);
    });

    test('is dialled again once it has been unplugged and put back', () async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.connectThrows = StateError('port busy');
      client.plugged();
      await settle();

      client.present = const [];
      client.plugged();
      await settle();

      client.present = [usb('A')];
      client.plugged();
      await settle();

      expect(client.dialled, ['usb:A', 'usb:A']);
    });
  });

  group('a link the app is holding', () {
    // The rule this file exists for. `_holdUsbIds` is set by the session
    // report, not by the setting, and it outlives the link: a Flipper that
    // rebooted into the updater or had its cable knocked out is taken back.
    test('comes back even with the setting off', () async {
      links = await serviceWith(usbAuto: false);
      client.present = [usb('A')];
      client.reportSessions([connected(usb('A'))]);
      await settle();
      expect(client.dialled, isEmpty, reason: 'it is already up');

      client.reportSessions(const []);
      client.plugged();
      await settle();

      expect(client.dialled, ['usb:A']);
    });

    test('is let go for good once the user lets it go', () async {
      links = await serviceWith(usbAuto: false);
      client.present = [usb('A')];
      client.reportSessions([connected(usb('A'))]);
      await settle();

      await links.disconnectDevice(usb('A'), id: 'A', link: FlipperLink.usb);
      client.reportSessions(const []);
      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });

    // The suppression is about this device while it is here. Unplugging it
    // ends the statement, so plugging it in again is a fresh question.
    test('is dialled again after it has been away', () async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      await links.disconnectDevice(usb('A'), id: 'A', link: FlipperLink.usb);
      client.plugged();
      await settle();
      expect(client.dialled, isEmpty, reason: 'the user just let it go');

      client.present = const [];
      client.plugged();
      await settle();
      client.present = [usb('A')];
      client.plugged();
      await settle();

      expect(client.dialled, ['usb:A']);
    });

    test('stops anything else being dialled while it is up', () async {
      links = await serviceWith(usbAuto: true, bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('B1'));
      client.present = [usb('A'), usb('C')];
      client.reportSessions([connected(usb('A'))]);

      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });
  });

  group('the remembered Flipper', () {
    test('is dialled when nothing is plugged in', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('B1'));

      client.plugged();
      await settle();

      expect(client.dialled, ['ble:B1']);
    });

    test('is not dialled while the setting is off', () async {
      links = await serviceWith(bleAuto: false);
      await KnownDevicesStore.instance.remember(ble('B1'));

      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });

    // Once per run, not once per reconcile. A radio that is off, or a Flipper
    // that is out of range, answers every attempt the same way, and the app
    // must not spend the session asking.
    test('is dialled once, however many times the cable moves', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('B1'));
      client.connectThrows = StateError('out of range');

      client.plugged();
      await settle();
      client.plugged();
      await settle();
      client.plugged();
      await settle();

      expect(client.dialled, ['ble:B1']);
    });

    test('is not dialled after the user let it go', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('B1'));

      await links.disconnectDevice(ble('B1'), id: 'B1', link: FlipperLink.ble);
      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });
  });
}
