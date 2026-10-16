// That the Tier 1 gate appears only when the app really has nothing to offer.
//
// This is the most dangerous decision in #351: it blacks out the entire app.
// Getting it wrong in one direction leaves an iPhone user on a dead screen
// with no explanation (the bug); getting it wrong in the other blacks out a
// working Android install over a permission that still has USB-OTG behind it.
//
// It was untestable as first written. `_bluetoothBlocks` read a static over
// `io.Platform.isIOS`, so on a Windows test host the blocking branch could
// never be reached and neither answer was pinned — even though
// `AppPermission.tier` had been made a pure function precisely so it could
// be. `PermissionCenter` now takes `bluetoothIsTheOnlyTransport`, which is
// the injection point that makes both platforms reachable from here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/permissions/permission.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firmware_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetFirmwareState();
    SharedPreferences.setMockInitialValues(const {});
  });

  /// Pumps the whole app around [permissions] and hands back the controller.
  ///
  /// The caller must end with [closeDevice]: `mountedDevice` builds a real
  /// `DeviceController`, which starts a DFU detector polling on a one-second
  /// timer wherever libusb is present, and the binding checks for live timers
  /// before `tearDown` runs. `device_scope_reach_test.dart` records the same
  /// trap.
  Future<DeviceController> pumpApp(
    WidgetTester tester,
    PermissionCenter permissions,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (device, client) = mountedDevice();
    await tester.pumpWidget(
      QUnleashedApp(
        client: client,
        diagnostics: DiagnosticsSettings(),
        permissions: permissions,
        device: device,
      ),
    );
    await tester.pump();
    return device;
  }

  testWidgets('iOS with Bluetooth refused shows the gate instead of the app', (
    tester,
  ) async {
    final permissions = PermissionCenter(bluetoothIsTheOnlyTransport: true)
      ..record(AppPermission.bluetooth, PermissionOutcome.denied);

    final device = await pumpApp(tester, permissions);
    final gateShown = find.text('Bluetooth access needed').evaluate().length;
    final recheckNote = find
        .textContaining('Checked again when you come back')
        .evaluate()
        .length;
    await closeDevice(tester, device);

    expect(gateShown, 1, reason: 'the whole app is replaced by the gate');
    expect(
      recheckNote,
      1,
      reason: 'and it promises the resume re-read that clears it',
    );
  });

  testWidgets('Android with the same denial keeps the app', (tester) async {
    // USB-OTG is still a route to a Flipper, so this is a feature gate the
    // device picker draws - not a reason to take the app away.
    final permissions = PermissionCenter(bluetoothIsTheOnlyTransport: false)
      ..record(AppPermission.bluetooth, PermissionOutcome.denied);

    final device = await pumpApp(tester, permissions);
    final gateShown = find.text('Bluetooth access needed').evaluate().length;
    await closeDevice(tester, device);

    expect(gateShown, 0);
  });

  testWidgets('iOS with no answer yet keeps the app', (tester) async {
    // The guard that matters most. `unknown` is the state on a fresh iOS
    // install before CoreBluetooth has been consulted, and blacking out the
    // app on it would be worse than the silence this replaces.
    final permissions = PermissionCenter(bluetoothIsTheOnlyTransport: true);

    final device = await pumpApp(tester, permissions);
    final gateShown = find.text('Bluetooth access needed').evaluate().length;
    await closeDevice(tester, device);

    expect(gateShown, 0);
  });

  testWidgets('iOS with Bluetooth unavailable keeps the app', (tester) async {
    // A simulator or a machine with no radio. There is nothing for the user
    // to grant, so a gate offering a settings button would be a dead end.
    final permissions = PermissionCenter(bluetoothIsTheOnlyTransport: true)
      ..record(AppPermission.bluetooth, PermissionOutcome.unavailable);

    final device = await pumpApp(tester, permissions);
    final gateShown = find.text('Bluetooth access needed').evaluate().length;
    await closeDevice(tester, device);

    expect(gateShown, 0);
  });

  testWidgets('granting it on a resume takes the gate down', (tester) async {
    // What the gate's own footnote promises, end to end: no restart.
    final permissions = PermissionCenter(bluetoothIsTheOnlyTransport: true)
      ..record(AppPermission.bluetooth, PermissionOutcome.denied);

    final device = await pumpApp(tester, permissions);
    expect(find.text('Bluetooth access needed'), findsOneWidget);

    permissions.record(AppPermission.bluetooth, PermissionOutcome.granted);
    await tester.pump();
    final gateShown = find.text('Bluetooth access needed').evaluate().length;
    await closeDevice(tester, device);

    expect(gateShown, 0, reason: 'the scope redrew the shell, not a restart');
  });
}
