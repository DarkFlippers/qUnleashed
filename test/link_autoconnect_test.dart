import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sentry_capture.dart';

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

  /// When set, `connect` hands this back instead of answering - so a case can
  /// press Disconnect while the dial is still in flight, which is the only way
  /// to reach the cancel path.
  Completer<FlipperDevice>? parkConnect;

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
    final park = parkConnect;
    if (park != null) return park.future;
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

  // What a reconnect reports, which for a while was nothing.
  //
  // `traced('device.connect')` sits inside `LinkService.connect()`, and both
  // auto paths bypass it - `_autoConnect` calls `_open` directly and the BLE
  // branch calls the client. So no automatic link produced a transaction at
  // all, including the BLE one that is on by default. A local build found it:
  // a session that had plainly connected had four spans in Sentry and not one
  // of them was a connect.
  group('what an automatic link reports', () {
    test('a cable dialled by itself is one device.connect.auto', () async {
      final sent = await captureTransactions();
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];

      client.plugged();
      await settle();
      await Sentry.close();

      final connects = sent.where((t) => t.name == 'device.connect.auto');
      expect(connects, hasLength(1));
      expect(connects.single.status, 'ok');
      // The one fact that splits "it took ages to connect", and the reason
      // this is a separate name from the manual `device.connect` rather than a
      // note on it: a link the app formed by itself is a different operation.
      expect(connects.single.data['link'], 'usb');
      expect(connects.single.data['trigger'], 'plugged in');
    });

    test('the remembered Flipper reports the same operation', () async {
      // The branch that is on by default, and the one whose `link` note is
      // hand-written rather than read off the device - `last` is a
      // `KnownDevice` and carries no link - so it is the one that can drift
      // from the USB branch's without anything noticing.
      final sent = await captureTransactions();
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('B1'));

      client.plugged();
      await settle();
      await Sentry.close();

      final connects = sent.where((t) => t.name == 'device.connect.auto');
      expect(connects, hasLength(1));
      expect(connects.single.status, 'ok');
      expect(connects.single.data['link'], 'ble');
      expect(connects.single.data['trigger'], 'remembered');
      expect(client.dialled, ['ble:B1']);
    });

    // A cancel is swallowed on purpose - it is not a fault - and that is
    // exactly what made it a lie here: `_open` returned normally, so the span
    // read `ok` and carried the whole duration of an attempt the user gave up
    // on. Attempts are given up on *because* they are hanging, so every one of
    // them landed in the tail of the distribution this operation exists to
    // measure. `TraceScope.failed` is the mechanism for an operation that did
    // not do what was asked without raising.
    test('a dial the user gives up on is not a connect that worked', () async {
      final sent = await captureTransactions();
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      final park = client.parkConnect = Completer<FlipperDevice>();

      client.plugged();
      await settle();
      // Pressed while it is still dialling, which is what makes this a cancel
      // rather than a disconnect.
      final pressed = links.disconnectDevice(
        usb('A'),
        id: 'A',
        link: FlipperLink.usb,
      );
      park.completeError(StateError('aborted'));
      await pressed;
      await settle();
      await Sentry.close();

      final connects = sent.where((t) => t.name == 'device.connect.auto');
      expect(connects, hasLength(1));
      // `cancelled` (499) and not `internal_error` (500), which is what this
      // asserted first: an alert on a connect that broke an invariant must not
      // fire because somebody changed their mind. Not `ok` either - the dial
      // did not happen, so its duration stays out of the success numbers.
      expect(connects.single.status, 'cancelled');
      expect(connects.single.data['failure'], 'cancelled');
    });

    test('a dial that fails is reported failed, not dropped', () async {
      // `traced` goes inside the `try`, so the catch that records the failure
      // still runs - and the span still carries the error. Putting `traced`
      // around the catch instead would report every failed reconnect as `ok`,
      // which is worse than not tracing it.
      final sent = await captureTransactions();
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.connectThrows = StateError('port busy');

      client.plugged();
      await settle();
      await Sentry.close();

      final connects = sent.where((t) => t.name == 'device.connect.auto');
      expect(connects, hasLength(1));
      // The exact status, not `isNot('ok')`: a span with no status at all
      // would pass that, and an unfilterable transaction is the thing this is
      // meant to rule out.
      expect(connects.single.status, 'internal_error');
      expect(client.dialled, [
        'usb:A',
      ], reason: 'and the existing behaviour is unchanged');
    });
  });

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

  /// What the device page has to show for an attempt nobody watched.
  ///
  /// Everything above is about *whether* the app dials. This is about what is
  /// left when it did and the Flipper said no: the attempt has no gesture
  /// behind it, so there is nothing to put a dialog on, and the condition
  /// outlives it - the id stays in `_autoTriedUsb` while the cable is in, so
  /// nothing dials again until something changes. Until #120 the only record
  /// was a log line, and the cable simply did nothing.
  group('an auto-connect that failed', () {
    Future<LinkService> failedUsbAttempt() async {
      final service = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.connectThrows = StateError('port busy');
      client.plugged();
      await settle();
      return service;
    }

    test('is kept, not only logged', () async {
      links = await failedUsbAttempt();

      expect(links.autoConnectFailure, isNotNull);
    });

    test('names the Flipper it was dialling', () async {
      links = await failedUsbAttempt();

      expect(links.autoConnectFailure?.name, 'A');
    });

    // The hint shows the same sentence the picker's dialog would, and that
    // sentence is chosen from this.
    test('keeps what was thrown', () async {
      links = await failedUsbAttempt();

      expect('${links.autoConnectFailure?.error}', contains('port busy'));
    });

    test('is not there when the attempt worked', () async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];

      client.plugged();
      await settle();

      expect(links.autoConnectFailure, isNull);
    });

    test('is not there before anything was attempted', () async {
      links = await serviceWith(usbAuto: true);

      expect(links.autoConnectFailure, isNull);
    });

    // Unplugging is also what lets the next appearance be dialled again, so
    // the hint would be describing a situation that no longer holds.
    test('goes when the Flipper is unplugged', () async {
      links = await failedUsbAttempt();

      client.present = const [];
      client.plugged();
      await settle();

      expect(links.autoConnectFailure, isNull);
    });

    test('goes when that Flipper comes up anyway', () async {
      links = await failedUsbAttempt();

      client.reportSessions([connected(usb('A'))]);
      await settle();

      expect(links.autoConnectFailure, isNull);
    });

    // A different Flipper connecting does not answer it. The sharp case in
    // #120 is exactly this: two links held, a third refused, and the page
    // looking entirely connected.
    test('stays while a different Flipper is the connected one', () async {
      links = await failedUsbAttempt();

      client.reportSessions([connected(usb('B'))]);
      await settle();

      expect(links.autoConnectFailure, isNotNull);
    });

    // The picker reports its own outcome, so there is nothing left for the
    // hint to say - whatever the hand-dialled attempt then does.
    test('goes when the user dials it themselves', () async {
      links = await failedUsbAttempt();

      await expectLater(links.connectDevice(usb('A')), throwsA(anything));

      expect(links.autoConnectFailure, isNull);
    });

    test('goes when the user puts it away', () async {
      links = await failedUsbAttempt();

      links.dismissAutoConnectFailure();

      expect(links.autoConnectFailure, isNull);
    });

    test('notifies when it arrives', () async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.connectThrows = StateError('port busy');
      var notified = 0;
      links.addListener(() => notified++);

      client.plugged();
      await settle();

      expect(notified, greaterThan(0));
    });

    test('is recorded for BLE too, and says so', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('B1'));
      client.connectThrows = StateError('out of range');

      client.plugged();
      await settle();

      expect(links.autoConnectFailure?.isBle, isTrue);
      expect(links.autoConnectFailure?.name, 'B1');
    });
  });
}
