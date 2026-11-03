import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/connect_report.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'known_device_ids.dart';
import 'sentry_capture.dart';
import 'telemetry_sinks.dart';

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

  /// Raised by the next `connect`, so a failed attempt can be watched. On
  /// the USB side it also emits the sessions it would in production, which
  /// schedules a reconcile - so a case that sets this gets one more pass than
  /// the plug count suggests. Read by `auto_connect_hint_test.dart` and
  /// `connect_transport_labels_test.dart` too, which import this fake.
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
    if (connectThrows != null) {
      // Faithful to flipperlib: a refused connect drops the session and
      // emits, and that emission is what schedules the next reconcile
      // (`establishLocked` -> `_dropSessionLocked`, then
      // `LinkService._onSessions`). Without it a test can reach a second
      // reconcile only by replugging, which is not the trigger production
      // uses. Not done on the BLE side, whose refusal stays emissionless -
      // the asymmetry is deliberate rather than considered.
      reportSessions(sessions);
      throw connectThrows!;
    }
    return device;
  }

  @override
  Future<FlipperDevice> connectBleAddress(
    String address, {
    String? name,
    Duration timeout = FlipperClient.bleAddressConnectTimeout,
  }) async {
    dialled.add('ble:$address');
    // Honours [parkConnect] like `connect` does, and it has to: the remembered
    // dial is the one path that reaches `_autoDial`'s catch on a cancel, so a
    // case cannot press Disconnect mid-dial without it.
    final park = parkConnect;
    if (park != null) return park.future;
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
  /// [stored] goes on disk as `known_devices_v1` before the service exists,
  /// for the cases that need a remembered device the service *read* rather
  /// than one handed to [KnownDevicesStore.remember] afterwards. The service
  /// loads the store itself from [LinkService.start], so seeding here is what
  /// drives the whole chain: disk, `_load`, `lastDevice`, `_autoDial`.
  ///
  /// That load is not awaited - it is `load().whenComplete(...)` - so what
  /// makes a seeded store observable is the [settle] the case does next, not
  /// this helper returning.
  Future<LinkService> serviceWith({
    bool usbAuto = false,
    bool bleAuto = false,
    List<Map<String, Object>> stored = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      if (stored.isNotEmpty) 'known_devices_v1': jsonEncode(stored),
    });
    final settings = DeviceSettings.instance..reset();
    await settings.load();
    await settings.setAutoConnectUsb(usbAuto);
    await settings.setAutoConnectBle(bleAuto);

    // No emptying of the store by hand: `test/flutter_test_config.dart` rewinds
    // it before every case, which is also what lets [stored] be read at all -
    // `load()` memoises, so a load spent here would have been the only one.
    // #452
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
      await KnownDevicesStore.instance.remember(ble('b1'));

      client.plugged();
      await settle();
      await Sentry.close();

      final connects = sent.where((t) => t.name == 'device.connect.auto');
      expect(connects, hasLength(1));
      expect(connects.single.status, 'ok');
      expect(connects.single.data['link'], 'ble');
      expect(connects.single.data['trigger'], 'remembered');
      expect(client.dialled, ['ble:b1']);
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

  // What the automatic paths hand ADR 0013 §2's counter, which the metric's
  // own test cannot see: it drives the hook directly, so every derivation at a
  // call site - the transport, the attempt, and whether a cancel reports at
  // all - is invisible to it. Deleting the whole `reportConnectFailure` block
  // from `_autoDial` left the entire suite green before this group.
  group('what a failed automatic link counts', () {
    /// One line per call the production hook made, as `attempt/transport/kind`.
    late List<String> counted;

    setUp(() {
      counted = [];
      connectFailureSink =
          (kind, error, stack, {required attempt, required isBle}) => counted
              .add('${attempt.name}/${transportLabel(isBle)}/${kind.name}');
    });

    tearDown(resetTelemetrySinks);

    test(
      'a remembered dial that failed is one auto attempt over ble',
      () async {
        links = await serviceWith(bleAuto: true);
        await KnownDevicesStore.instance.remember(ble('b1'));
        client.connectThrows = StateError('connection timed out');

        client.plugged();
        await settle();

        expect(counted, ['auto/ble/deviceUnreachable']);
      },
    );

    test('a cable the app dialled and lost is one auto attempt over usb', () async {
      // The other derivation, and the pair is the point: `_autoDial` reads the
      // transport off the enum it was handed, not off the device, because a
      // `KnownDevice` carries no link. Inverting it mislabels every automatic
      // failure, and the dimension it mislabels is the one the whole analysis
      // splits on.
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.connectThrows = StateError('port busy');

      client.plugged();
      await settle();

      expect(counted, ['auto/usb/unknown']);
    });

    test('a remembered dial the user calls off counts nowhere', () async {
      // The regression this group exists for: the remembered dial sets no
      // activity, so the abort reaches its catch like any other failure and
      // filed an issue per cancel. `LinkService._recordAutoFailure` has the
      // mechanism and ADR 0013 the decision.
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('b1'));
      final park = client.parkConnect = Completer<FlipperDevice>();

      client.plugged();
      await settle();
      final pressed = links.disconnectDevice(
        ble('b1'),
        id: 'b1',
        link: FlipperLink.ble,
      );
      park.completeError(StateError('BLE connect aborted'));
      await pressed;
      await settle();

      expect(counted, isEmpty);
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
      await KnownDevicesStore.instance.remember(ble('b1'));
      client.present = [usb('A'), usb('C')];
      client.reportSessions([connected(usb('A'))]);

      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });
  });

  /// The half of a hold nobody asked for. #460.
  ///
  /// The cases above about a hold have a user behind it - they report the
  /// session rather than letting the app dial - and the rule there is that a
  /// setting flipped afterwards does not take it back.
  /// Since #458 the app dials a cable at launch by itself, and that link
  /// entered the same set - so the hold tier went on taking it back after the
  /// user turned the setting off, on behalf of nobody. These cases are about
  /// which statements count as the user asking for the link after all, and
  /// the install path is one of them rather than a courtesy: `awaitUsbReturn`
  /// has no deadline, so a hold that stood down on its return would hang an
  /// install for good.
  group('a USB link the app formed by itself', () {
    /// The premise the whole group rests on: the app dials the cable, nobody
    /// having asked, and the session report makes it a hold like any other.
    Future<void> appDialled() async {
      links = await serviceWith(usbAuto: true);
      client.present = [usb('A')];
      client.plugged();
      await settle();
      expect(client.dialled, [
        'usb:A',
      ], reason: 'premise: the app dialled this cable by itself');

      client.reportSessions([connected(usb('A'))]);
      await settle();
    }

    /// Out and back in, which is the user's own repro and the only thing that
    /// makes the cable a question again: the link is gone, so nothing is held,
    /// and the absence prunes `_autoTriedUsb`.
    Future<void> replug() async {
      client.reportSessions(const []);
      client.present = const [];
      client.plugged();
      await settle();
      client.present = [usb('A')];
      client.plugged();
      await settle();
    }

    // The tier is still one tier, and an app-formed hold is still in it: the
    // setting that formed the link is on, so taking it back is what it asked
    // for. Dropping app-formed entries from the hold tier outright would
    // leave this cable dialled by nothing at all - the tier below skips
    // everything `_holdUsbIds` holds.
    test('is taken back while the setting is still on', () async {
      await appDialled();

      await replug();

      expect(client.dialled, ['usb:A', 'usb:A']);
    });

    // The bug. Written against the old code first, where the second dial
    // happened with `trigger: 'holding this one'`.
    test('is not taken back once the user turns the setting off', () async {
      await appDialled();
      await DeviceSettings.instance.setAutoConnectUsb(false);

      await replug();

      expect(client.dialled, ['usb:A']);
    });

    // And what makes it an endorsement set rather than a flag. The user
    // pressing Connect is the statement the hold tier exists for, whoever
    // dialled the cable first.
    test('is taken back once the user has asked for it by hand', () async {
      await appDialled();
      await DeviceSettings.instance.setAutoConnectUsb(false);
      await replug();
      expect(client.dialled, ['usb:A'], reason: 'premise: it stood down');

      final entry = links.entries.firstWhere((e) => e.isUsb && e.id == 'A');
      await links.connect(entry);
      expect(client.dialled, [
        'usb:A',
        'usb:A',
      ], reason: 'premise: and the user dialled it themselves');
      client.reportSessions([connected(usb('A'))]);
      await settle();

      await replug();

      expect(client.dialled, ['usb:A', 'usb:A', 'usb:A']);
    });

    // The other by-hand path: the picker dialog, which dials the device it
    // was handed rather than a row of the connection list. Both are real -
    // `connectPickedDevice` for this one, `connectLinkEntry` for the case
    // above - and they reach `LinkService` through different methods, so one
    // case cannot stand in for the other.
    test('is taken back when the user picks it out of the dialog', () async {
      await appDialled();
      await DeviceSettings.instance.setAutoConnectUsb(false);
      await replug();
      expect(client.dialled, ['usb:A'], reason: 'premise: it stood down');

      await links.connectDevice(usb('A'));
      client.reportSessions([connected(usb('A'))]);
      await settle();

      await replug();

      expect(client.dialled, ['usb:A', 'usb:A', 'usb:A']);
    });

    // And it stays theirs. Taking a hold back records nothing deliberately:
    // if that counted as the app forming the link, an endorsed hold would
    // survive exactly one knocked-out cable with the setting off, and the
    // case above cannot tell - the dial it asserts happens before the
    // recording would.
    test('stays the user\'s once it has been taken back', () async {
      await appDialled();
      await DeviceSettings.instance.setAutoConnectUsb(false);
      await replug();

      final entry = links.entries.firstWhere((e) => e.isUsb && e.id == 'A');
      await links.connect(entry);
      client.reportSessions([connected(usb('A'))]);
      await settle();
      expect(client.dialled, [
        'usb:A',
        'usb:A',
      ], reason: 'premise: the user asked for this link');

      await replug();
      await replug();

      expect(client.dialled, ['usb:A', 'usb:A', 'usb:A', 'usb:A']);
    });

    // The origin does not outlive the hold: `disconnectDevice` lets go of
    // both. So a link that comes back without either writer having run - a
    // session flipperlib restored under the app, an activation from
    // elsewhere - is not still answered by the dial that formed the one
    // before it.
    test('loses its origin when the user lets the link go', () async {
      await appDialled();
      await links.disconnectDevice(usb('A'), id: 'A', link: FlipperLink.usb);
      await DeviceSettings.instance.setAutoConnectUsb(false);

      client.reportSessions([connected(usb('A'))]);
      await settle();

      await replug();

      expect(client.dialled, ['usb:A', 'usb:A']);
    });

    // The constraint #460 had to keep: the installer sends the Flipper into
    // the updater and waits for the port to come back, and that wait is only
    // over when the link is up again. With the setting off and nothing
    // endorsing the link, the app-formed hold would stand down on the return
    // and `awaitUsbReturn` - deliberately deadline-free - would never end.
    test(
      'is taken back across an install, whatever the setting says',
      () async {
        await appDialled();
        await DeviceSettings.instance.setAutoConnectUsb(false);

        final returned = links.awaitUsbReturn(usb('A'));
        await replug();

        expect(client.dialled, ['usb:A', 'usb:A']);

        // And the wait the install is sitting in ends, rather than this case
        // passing on a dial with nobody behind it.
        client.reportSessions([connected(usb('A'))]);
        await returned;
      },
    );
  });

  group('the remembered Flipper', () {
    test('is dialled by the canonical id, under the remembered name', () async {
      // The whole chain #444 is about, in one case: an upper-case id as a
      // build on universal_ble 2.x wrote it, sitting on disk, through `_load`
      // and `lastDevice` and `_autoDial` to the address handed to
      // `connectBleAddress`.
      //
      // It used to start at `remember` - the id came from `fromDevice`, not
      // off disk - because `serviceWith` cleared the store, and the load side
      // was covered separately. The two met in the middle and nothing drove
      // the join. #452 made the store's memo resettable, which is what seeding
      // disk here needs.
      links = await serviceWith(
        bleAuto: true,
        stored: [
          storedEntry(storedById, 'Flipper Zoe', '2026-10-01T10:00:00.000'),
        ],
      );

      client.plugged();
      await settle();

      expect(client.dialled, ['ble:$reportedById']);
      // A name that is not the id, which is two claims in one assertion: the
      // row's name comes from the stored `name` field, and the fold was
      // applied to the id and not to it - `canonicalBleDeviceId` lower-cases,
      // so a fold on this field would read `flipper zoe`. Every other case in
      // this file sets `name == id` through `ble()` and so can tell neither.
      expect(links.entries.single.name, 'Flipper Zoe');
    });

    test('is dialled when nothing is plugged in', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('b1'));

      client.plugged();
      await settle();

      expect(client.dialled, ['ble:b1']);
    });

    test('is not dialled while the setting is off', () async {
      links = await serviceWith(bleAuto: false);
      await KnownDevicesStore.instance.remember(ble('b1'));

      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });

    // The ordering is not new - the USB branch has always returned before
    // the remembered device. What changed is the default: with
    // `autoConnectUsb` off the candidate list was empty, so control fell
    // through to the radio with the Flipper sitting on a cable.
    test('is not dialled past a Flipper on the cable', () async {
      links = await serviceWith(usbAuto: true, bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('b1'));
      client.present = [usb('A')];

      client.plugged();
      await settle();

      expect(client.dialled, ['usb:A']);
    });

    // The other side of that ordering, and what keeps a cable the app cannot
    // open - a declined USB prompt, a port another process holds - from
    // costing the user every link: the id stays in `_autoTriedUsb`, so the
    // reconcile the refusal itself schedules skips the cable and the radio
    // gets its turn. Driven by the session emission rather than a replug,
    // because that is the trigger production has; the hint is asserted so the
    // refusal is load-bearing rather than decoration - without it a dial that
    // *worked* would leave `dialled` looking exactly the same, this fake
    // reporting no session either way.
    test('gets its turn once the cable has refused', () async {
      links = await serviceWith(usbAuto: true, bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('b1'));
      client.present = [usb('A')];
      client.connectThrows = StateError('USB permission denied');

      client.plugged();
      await settle();

      expect(
        client.dialled,
        ['usb:A'],
        reason:
            'settle is 400ms and the debounce 250ms, so the rescheduled '
            'pass has not landed yet',
      );
      expect(
        links.autoConnectFailure?.name,
        'A',
        reason: 'and it refused - a dial that worked looks the same in dialled',
      );

      // No second plug: the refusal's own emission scheduled this pass.
      await settle();

      expect(client.dialled, ['usb:A', 'ble:b1']);
    });

    // Once per run, not once per reconcile. A radio that is off, or a Flipper
    // that is out of range, answers every attempt the same way, and the app
    // must not spend the session asking.
    test('is dialled once, however many times the cable moves', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('b1'));
      client.connectThrows = StateError('out of range');

      client.plugged();
      await settle();
      client.plugged();
      await settle();
      client.plugged();
      await settle();

      expect(client.dialled, ['ble:b1']);
    });

    test('is not dialled after the user let it go', () async {
      links = await serviceWith(bleAuto: true);
      await KnownDevicesStore.instance.remember(ble('b1'));

      await links.disconnectDevice(ble('b1'), id: 'b1', link: FlipperLink.ble);
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
  // The safety property the default rests on, and the Bluetooth half of the
  // case above: `held` is computed from every session rather than the USB
  // ones, so a cable appearing cannot pull the user off a Bluetooth link that
  // is already up. Scoping `held` to USB would otherwise keep the suite green.
  // `bleAuto` is left off deliberately - nothing is remembered here, so the
  // radio is not a candidate either way and `held` is the only thing that can
  // make the cable stand down.
  group('a Bluetooth link the app is holding', () {
    test('stops a cable being dialled', () async {
      links = await serviceWith(usbAuto: true);
      client.reportSessions([connected(ble('b1'))]);
      client.present = [usb('A')];

      client.plugged();
      await settle();

      expect(client.dialled, isEmpty);
    });
  });

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
      await KnownDevicesStore.instance.remember(ble('b1'));
      client.connectThrows = StateError('out of range');

      client.plugged();
      await settle();

      expect(links.autoConnectFailure?.isBle, isTrue);
      expect(links.autoConnectFailure?.name, 'b1');
    });
  });
}
