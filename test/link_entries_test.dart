import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The connection list, which is what a user picks a Flipper from.
///
/// `LinkService` is 500 lines of link decisions with no tests, and this is the
/// part of it that reaches the screen. It could not be exercised before: the
/// constructor is private and `start` is one-shot, so a second case would have
/// inherited the first one's client and its sessions.
/// `LinkService.forTest` is that seam, and `instance` is untouched.
///
/// Not covered here: auto-connect, which is the other half of `_reconcile` and
/// wants its own file - it is about what the service does on its own rather
/// than what it shows.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id, this.transport);

  @override
  final String id;

  @override
  String get name => id;

  @override
  final DeviceTransport transport;
}

FlipperDevice usb(String id, {String name = ''}) => FlipperDevice(
  id: id,
  name: name.isEmpty ? id : name,
  link: FlipperLink.usb,
  source: _Discovered(id, DeviceTransport.usb),
);

FlipperDevice ble(String id, {String name = ''}) => FlipperDevice(
  id: id,
  name: name.isEmpty ? id : name,
  link: FlipperLink.ble,
  source: _Discovered(id, DeviceTransport.ble),
);

FlipperSessionInfo held(
  FlipperDevice device, {
  bool connected = true,
  bool connecting = false,
  bool active = true,
}) => FlipperSessionInfo(
  device: device,
  connected: connected,
  connecting: connecting,
  active: active,
);

class FakeLinkClient implements FlipperClient {
  final _usbEvents = StreamController<void>.broadcast();
  final _sessions = StreamController<List<FlipperSessionInfo>>.broadcast();
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _heard = StreamController<FlipperDevice>.broadcast();

  /// Everything the platform reports, USB and BLE alike. `_refreshUsb` filters
  /// it down, which is one of the things worth pinning.
  List<FlipperDevice> present = const [];

  @override
  List<FlipperSessionInfo> sessions = const [];

  /// Names the client learnt from a device, which win over the discovered one.
  final Map<String, String> names = {};

  Future<void> close() async {
    await _usbEvents.close();
    await _sessions.close();
    await _connection.close();
    await _heard.close();
  }

  /// A cable event, which is what drives a re-enumeration.
  void plugged() => _usbEvents.add(null);

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
  bool isFlipperDevice(FlipperDevice device) => !device.id.startsWith('other');

  @override
  String? getNameOf(FlipperDevice device) => names[device.id];

  @override
  Future<List<FlipperDevice>> refreshUsbOnly() async => present;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLinkClient client;
  late LinkService links;

  setUp(() async {
    // Auto-connect off. These cases are about what the list shows; with it on
    // the reconcile also tries to dial the remembered BLE device, which the
    // fake refuses and which has nothing to do with any assertion here.
    SharedPreferences.setMockInitialValues(const {
      'flutter.device.autoconnect.usb': false,
      'flutter.device.autoconnect.ble': false,
    });
    client = FakeLinkClient();
    links = LinkService.forTest(client);
    addTearDown(() async {
      links.dispose();
      await client.close();
    });
    // The store is a singleton and outlives the case, so each one starts by
    // dropping what the last one remembered.
    final known = KnownDevicesStore.instance;
    await known.load();
    for (final device in [...known.devices]) {
      await known.forget(device);
    }
  });

  /// Lets the debounced re-enumeration run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  group('what the USB half shows', () {
    test('is the Flippers the platform reports', () async {
      client.present = [usb('A'), usb('B')];

      client.plugged();
      await settle();

      expect(links.entries.map((e) => e.id), ['A', 'B']);
      expect(links.entries.every((e) => e.isUsb), isTrue);
    });

    // A cable can carry anything. The enumeration is everything plugged in,
    // not everything that is a Flipper.
    test('is not everything on the bus', () async {
      client.present = [usb('A'), usb('other-mouse')];

      client.plugged();
      await settle();

      expect(links.entries.map((e) => e.id), ['A']);
    });

    test('leaves BLE devices to the other half', () async {
      client.present = [usb('A'), ble('B')];

      client.plugged();
      await settle();

      expect(links.entries.map((e) => e.id), [
        'A',
      ], reason: 'a BLE device is shown because it is remembered, not present');
    });

    test('is sorted by name, not by enumeration order', () async {
      client.present = [usb('z', name: 'Zulu'), usb('a', name: 'Alpha')];

      client.plugged();
      await settle();

      expect(links.entries.map((e) => e.name), ['Alpha', 'Zulu']);
    });

    // The device the client has talked to knows its own name; the discovered
    // one is whatever the OS called the port.
    test('prefers the name the client learnt', () async {
      client.present = [usb('A', name: 'usb-serial-1420')];
      client.names['A'] = 'Kitchen';

      client.plugged();
      await settle();

      expect(links.entries.single.name, 'Kitchen');
    });

    test('reports a held session on a present device', () async {
      client.present = [usb('A')];
      client.sessions = [held(usb('A'))];

      client.plugged();
      await settle();

      final entry = links.entries.single;
      expect(entry.session, LinkSession.active);
      expect(entry.held, isTrue);
    });

    // The link survives the enumeration: a Flipper that stopped answering the
    // bus but whose session is still up must not vanish from the list, or the
    // user has no way to let it go.
    test('keeps a session whose device is no longer enumerated', () async {
      client.present = const [];
      client.sessions = [held(usb('A'))];

      client.plugged();
      await settle();

      expect(links.entries.map((e) => e.id), ['A']);
      expect(links.entries.single.held, isTrue);
    });

    test('does not show it twice when it is both', () async {
      client.present = [usb('A')];
      client.sessions = [held(usb('A'))];

      client.plugged();
      await settle();

      expect(links.entries, hasLength(1));
    });
  });

  group('what the BLE half shows', () {
    setUp(() async {
      await KnownDevicesStore.instance.remember(ble('B1', name: 'Bench'));
    });

    // BLE presence is evidence, not enumeration: a remembered device is listed
    // whether or not the radio has heard it, and `heard` is the difference.
    test('is what is remembered, heard or not', () async {
      client.plugged();
      await settle();

      final entry = links.entries.single;
      expect(entry.id, 'B1');
      expect(entry.isBle, isTrue);
      expect(entry.heard, isFalse);
    });

    test('is heard once a session holds it', () async {
      client.sessions = [held(ble('B1'))];

      client.plugged();
      await settle();

      expect(links.entries.single.heard, isTrue);
    });

    test('comes after the USB half', () async {
      client.present = [usb('A')];

      client.plugged();
      await settle();

      expect(links.entries.map((e) => e.id), ['A', 'B1']);
    });

    test('carries the remembered name, not the session one', () async {
      client.sessions = [held(ble('B1', name: 'whatever the radio said'))];

      client.plugged();
      await settle();

      expect(links.entries.single.name, 'Bench');
    });
  });

  test('a row is keyed by link and id, so the two halves cannot collide', () {
    expect(
      LinkEntry(
        id: 'X',
        link: FlipperLink.usb,
        name: 'X',
        address: 'X',
        session: LinkSession.none,
        heard: true,
        activity: LinkActivity.idle,
      ).key,
      'usb:X',
    );
  });
}
