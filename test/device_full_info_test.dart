import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/page.dart';
import 'package:qunleashed/pages/devices/widgets/cards/device_info_card.dart';
import 'package:qunleashed/pages/devices/widgets/page_header.dart';
import 'package:qunleashed/services/localization/l10n.dart';

import 'archive_fakes.dart';
import 'firmware_fixture.dart';

/// The device screen's "Full Info" sheet, which had no runtime coverage.
///
/// Recorded as a gap in #407's PR and filed with #413: the sheet is reachable
/// only when `ctrl.isConnected`, which the fixture could not produce until
/// `arriveWithDevice`.
///
/// What is worth pinning here is not that a sheet appears - it is
/// `_openFullInfo`'s **snapshot**. It reads `ctrl.deviceInfoEntries` several
/// times and `ctrl.info` once, all in the one call, and bakes the result into
/// a pushed route; the comment on it says that is deliberate, because there is
/// nothing in a pushed static sheet for a later notification to update.
///
/// **It does not pin the `notifierOf` read**, and it cannot: swapping that
/// call for the listening `DeviceScope.of` survives the case below, because
/// the subscription it would add belongs to the *page's* element - which
/// already depends on the scope from the first line of `build` - and the
/// sheet is built once from the snapshot either way. What holds that read in
/// place is the census in `test/device_scope_listen_test.dart`. #407.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// The device screen on a phone, with a Flipper connected and [info] on it.
  ///
  /// Narrow on purpose: `DeviceInfoCard`, which carries the button, is built
  /// by `_ConnectedContent` only `if (!wide)`. The hero's own button at 560
  /// and above opens the same method, and cannot be asserted on the same way -
  /// see #417.
  Future<(DeviceController, FakeFlipperClient)> pumpDevicePage(
    WidgetTester tester, {
    bool connected = true,
    Map<String, String> info = const {
      'hardware_name': archiveTestDevice,
      'firmware_version': '1.3.4',
      'hardware_uid': 'A1B2C3D4',
    },
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (device, client) = mountedDevice();
    await tester.pumpWidget(wrapWithDevice(const DeviceTab(), device));
    if (connected) client.arriveWithDevice(info: info);
    await settle(tester);
    return (device, client);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text(l10n.deviceFullInfo).first);
    await settle(tester);
  }

  /// [finder] inside the sheet, not on the screen behind it.
  ///
  /// Load-bearing, and the first draft of this file was wrong without it:
  /// `DeviceInfoCard` lists the same entries on the page, so an unscoped
  /// `find.text('1.3.4')` matches the card underneath - and the case below
  /// that claims the sheet ignores a later patch passed for a while by
  /// reading the card that had followed it.
  Finder inSheet(Finder finder) => find.descendant(
    of: find.byType(DraggableScrollableSheet),
    matching: finder,
  );

  testWidgets('opens on the connected device screen and shows the info', (
    tester,
  ) async {
    final (device, _) = await pumpDevicePage(tester);

    await openSheet(tester);

    expect(inSheet(find.text(l10n.deviceRawData)), findsOneWidget);
    // The raw card lists the info map by key, sorted - so these are the
    // controller's own values arriving through `ctrl.info`.
    expect(inSheet(find.text('hardware_uid')), findsOneWidget);
    expect(inSheet(find.text('A1B2C3D4')), findsOneWidget);
    // And the firmware card above it, built from `deviceInfoEntries`.
    expect(inSheet(find.text(l10n.infoFirmwareVersion)), findsOneWidget);
    expect(inSheet(find.text('1.3.4')), findsWidgets);

    await closeDevice(tester, device);
  });

  // The snapshot, which is the whole of why a non-listening read is correct
  // there. A patch that arrives after the sheet is pushed reaches the screen
  // behind it and not the sheet.
  testWidgets('keeps the values it was opened with', (tester) async {
    final (device, client) = await pumpDevicePage(tester);
    await openSheet(tester);
    expect(inSheet(find.text('1.3.4')), findsWidgets);

    client.publish(const {'firmware_version': '1.4.0'});
    await settle(tester);

    expect(
      inSheet(find.text('1.4.0')),
      findsNothing,
      reason: 'the sheet followed a patch it was not built to follow',
    );
    expect(inSheet(find.text('1.3.4')), findsWidgets);
    expect(
      find.text('1.4.0'),
      findsWidgets,
      reason: 'the patch reached nothing at all, so the sheet proves nothing',
    );

    await closeDevice(tester, device);
  });

  // The guard on the button, and the control for everything above: with
  // nothing connected `_ConnectedContent` is not built at all, so there is no
  // sheet to open rather than an empty one.
  testWidgets('is not reachable with nothing connected', (tester) async {
    final (device, _) = await pumpDevicePage(tester, connected: false);

    expect(find.text(l10n.deviceFullInfo), findsNothing);
    // The control. `findsNothing` on its own is also satisfied by a page that
    // failed to build, or by the string being renamed - so this says the
    // screen is up and it is the *disconnected* one.
    expect(find.byType(DevicePageHeader), findsOneWidget);
    expect(find.byType(DeviceInfoCard), findsNothing);

    await closeDevice(tester, device);
  });
}
