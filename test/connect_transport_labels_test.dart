// What the two connect surfaces say about the transports they are not using.
//
// #381: a phone docked in Samsung DeX showed nothing about Bluetooth on the
// device page, and the reporter - who wrote that he "wasn't even entirely sure
// bluetooth was supported" - reached a Bluetooth connection only by accident
// through another screen. Neither surface was a transport fault, and neither
// said anything.
//
// The device card lists plugged-in Flippers plus Bluetooth ones already
// connected once, so with nothing remembered the only Bluetooth affordance is
// the Search row - and that row said just "Search". The command line's picker,
// the second surface the triage found, narrows itself to USB deliberately
// (`supportsCli` is false on the BLE link) and said nothing about why, after
// the dialog that used to say it was removed in aa55e5c4.
//
// Both are strings, which is exactly why they are pinned here: a label is the
// first thing a refactor drops and the last thing anybody notices, and the
// absence of this one has already been read as a missing feature.
import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/dialogs/connection.dart';
import 'package:qunleashed/pages/devices/widgets/cards/connect_card.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_autoconnect_test.dart' show FakeDialClient, usb;

/// [FakeDialClient] with the four members the picker touches and the service
/// does not: it watches the device list, asks for Bluetooth access, scans, and
/// stops the scan when it closes.
///
/// [initialize] answering [BleAccess.granted] is load-bearing rather than
/// decorative: a refusal puts a `PermissionNotice` where the list goes, so a
/// case about the header would be asserting against the wrong screen.
///
/// Note for anyone extending this: the picker's own Disconnect reaches
/// `LinkService.instance`, not this client, so a held-session case needs more
/// than a fake here.
class FakePickerClient extends FakeDialClient {
  final _devices = StreamController<List<FlipperDevice>>.broadcast();

  @override
  Stream<List<FlipperDevice>> get devicesStream => _devices.stream;

  @override
  Future<BleAccess> initialize() async => BleAccess.granted;

  @override
  Future<List<FlipperDevice>> refreshDevices({
    Duration bleTimeout = const Duration(seconds: 10),
  }) async => present;

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> close() async {
    await _devices.close();
    await super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
    // The surfaces read the app's colour extension, so a bare MaterialApp
    // renders either of them as a null check on a missing theme.
    theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
    home: Scaffold(body: child),
  );

  /// Both groups tear the tree down before asserting, so every case reads what
  /// it is about into a plain value first.
  int shown(String text) => find.text(text).evaluate().length;

  /// A device row, counted by its transport icon rather than its name: the row
  /// prints the name over the address, and the fake's device carries the same
  /// string for both.
  int rows(IconData icon) => find.byIcon(icon).evaluate().length;

  group('the device card', () {
    late FakeDialClient client;

    setUp(() {
      client = FakeDialClient();
      addTearDown(() async => client.close());
    });

    /// A started service with the stores it reads reset for this case, and
    /// nothing remembered over Bluetooth - the state the report was filed in.
    ///
    /// Driven inside [WidgetTester.runAsync] and disposed in the body, for the
    /// two reasons `auto_connect_hint_test.dart` sets out: the reconcile
    /// debounce is a real `Timer` the fake clock never reaches, and the
    /// binding checks for live timers before `tearDown` runs.
    Future<LinkService> started(WidgetTester tester) async {
      late LinkService links;
      await tester.runAsync(() async {
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
        links = LinkService.forTest(client);
        client.plugged();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      return links;
    }

    Future<void> closeCard(WidgetTester tester, LinkService links) async {
      await tester.pumpWidget(const SizedBox());
      links.dispose();
    }

    testWidgets('names Bluetooth with nothing remembered', (tester) async {
      final links = await started(tester);

      await tester.pumpWidget(wrap(ConnectCard(links: links)));
      final search = shown(l10n.connectSearch);
      final bluetooth = shown(l10n.connectSearchSubtitle);
      await closeCard(tester, links);

      expect(search, 1);
      expect(bluetooth, 1);
    });

    // A Flipper on the cable and none remembered over Bluetooth: the card has
    // a row, so it reads as a list of what the app can reach - and without the
    // subtitle that list is USB and nothing else, which is the whole of #381.
    // The dock's own serial interfaces never get this far, by the way:
    // `_refreshUsb` keeps only what `isFlipperDevice` admits.
    testWidgets('still names Bluetooth beside a USB row', (tester) async {
      client.present = [usb('A')];
      final links = await started(tester);

      await tester.pumpWidget(wrap(ConnectCard(links: links)));
      final usbRows = rows(Icons.usb);
      final bleRows = rows(Icons.bluetooth) + rows(Icons.bluetooth_connected);
      final bluetooth = shown(l10n.connectSearchSubtitle);
      await closeCard(tester, links);

      expect(usbRows, 1, reason: 'the Flipper on the cable');
      expect(bleRows, 0, reason: 'no Bluetooth row of any kind');
      expect(bluetooth, 1);
    });
  });

  group('the picker', () {
    /// Leaves no dialog mounted: its `dispose` stops the scan through
    /// `guarded`, and letting that land during binding teardown races the
    /// `client.close()` closing the controllers it reads.
    Future<void> closeDialog(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }

    FakePickerClient picker() {
      final client = FakePickerClient();
      addTearDown(() async => client.close());
      return client;
    }

    testWidgets('says why a USB-only list has no Bluetooth', (tester) async {
      // With a row under it, so the header carries the device list's height
      // pressure - which is what the reason line introduced and what the
      // column above it is there to absorb.
      final client = picker()..present = [usb('A')];

      await tester.pumpWidget(
        wrap(ConnectionDialog(client: client, usbOnly: true)),
      );
      await tester.pumpAndSettle();
      final titled = shown(l10n.pickerSelectUsbDevice);
      final reason = shown(l10n.pickerUsbOnlyReason);
      final listed = rows(Icons.usb);
      await closeDialog(tester);

      expect(titled, 1);
      expect(reason, 1);
      expect(listed, 1, reason: 'the row under the header');
    });

    // The line answers the narrowing and nothing else, so the picker that
    // lists both transports must not carry it - there is nothing to explain.
    testWidgets('says nothing extra when nothing was narrowed', (tester) async {
      final client = picker();

      await tester.pumpWidget(wrap(ConnectionDialog(client: client)));
      await tester.pumpAndSettle();
      final titled = shown(l10n.pickerSelectDevice);
      final reason = shown(l10n.pickerUsbOnlyReason);
      await closeDialog(tester);

      expect(titled, 1);
      expect(reason, 0);
    });
  });
}
