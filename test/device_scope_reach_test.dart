import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';
import 'package:qunleashed/pages/option/diagnostics_scope.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/permissions/scope.dart';
import 'package:qunleashed/services/telemetry/settings.dart';

import 'firmware_fixture.dart';

/// That a pushed route can reach the scopes — ADR 0011.
///
/// `DeviceScope` used to be mounted by `AppShell`, which is
/// `MaterialApp.home`: route `/` inside the Navigator. A route pushed on top
/// is that route's sibling rather than its descendant, so everything reached
/// by a push was outside the scope. `lib/` has 25 pushes, and exactly one of
/// them — `FirmwareCard._openChangelog` — re-provided the scope by hand.
///
/// It is provided through `MaterialApp.builder` now, which wraps the
/// Navigator. The two cases below are the before and after of that: the first
/// is what the app does, the second is what it used to do, kept so the
/// difference is a test rather than a paragraph.
///
/// `DiagnosticsScope` is checked in the same place and for the same reason.
/// ADR 0013 §1 puts the reporting switch on the settings screen, which is
/// reached by a push through the `AppRoute` registry - so it is one of the 25
/// that the first shape above would have left outside.
///
/// `PermissionScope` joins them for a third version of the same reason, and
/// it is the one with the sharpest failure. Every surface that draws a
/// permission notice is reached by a push - Settings → Storage, Settings →
/// Push, the IR library dialog - and a notice outside the scope draws
/// *nothing at all* rather than throwing, because `maybeOf` returning null
/// is the same silence an ungranted permission produces. That is precisely
/// the failure #351 exists to end, so it is pinned here rather than left to
/// be noticed on a device.
///
/// Both end with [closeDevice]. `mountedDevice` builds a real
/// `DeviceController`, which starts a DFU detector that polls on a one-second
/// timer wherever libusb is present - Linux CI, not a Windows dev box. The
/// binding checks for live timers before tearDown runs, so disposing from a
/// teardown is too late and the failure is platform-dependent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// The controller found at [key]'s context, or null if there is no scope.
  DeviceController? reachedFrom(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    return context.dependOnInheritedWidgetOfExactType<DeviceScope>()?.notifier;
  }

  /// The client [DeviceScope.clientOf] finds at [key]'s context.
  ///
  /// The reach above is asserted through `dependOn...`, which is what `of`
  /// uses. Since #344 the thirty client-only sites go through `clientOf` and
  /// its `getInheritedWidgetOfExactType` instead, so the accessor most of
  /// `lib/` now depends on is checked here too. The two resolve through the
  /// same `_inheritedElements` map, which is the reason this is one line
  /// rather than a case of its own.
  FlipperClient? clientReachedFrom(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    return DeviceScope.clientOf(context);
  }

  /// The reporting switch found at [key]'s context, or null if there is no
  /// scope.
  DiagnosticsSettings? switchReachedFrom(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    return context
        .dependOnInheritedWidgetOfExactType<DiagnosticsScope>()
        ?.notifier;
  }

  /// The permission record found at [key]'s context, or null if there is
  /// no scope.
  PermissionCenter? permissionsReachedFrom(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    return context
        .dependOnInheritedWidgetOfExactType<PermissionScope>()
        ?.notifier;
  }

  testWidgets('a route pushed over the app is inside the scope', (
    tester,
  ) async {
    final (device, client) = mountedDevice();
    final key = GlobalKey();
    final diagnostics = DiagnosticsSettings();
    final permissions = PermissionCenter();

    await tester.pumpWidget(
      QUnleashedApp(
        client: client,
        diagnostics: diagnostics,
        permissions: permissions,
        device: device,
      ),
    );
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaitedPush(navigator, key);
    await tester.pumpAndSettle();

    // Read before the tree goes, asserted after: `closeDevice` has to run
    // whatever this says, or a failure here is reported as a pending timer.
    final reached = reachedFrom(key);
    final reachedClient = clientReachedFrom(key);
    final reachedSwitch = switchReachedFrom(key);
    final reachedPermissions = permissionsReachedFrom(key);
    await closeDevice(tester, device);

    expect(
      reached,
      same(device),
      reason: 'the same controller the shell reads, not a second one',
    );
    expect(
      reachedClient,
      same(client),
      reason: 'and the accessor the thirty converted sites use finds it too',
    );
    expect(
      reachedSwitch,
      same(diagnostics),
      reason: 'the same switch Telemetry follows, not a second one',
    );
    expect(
      reachedPermissions,
      same(permissions),
      reason:
          'the same record the storage path writes to, not a second '
          'one - a notice reading an empty copy draws nothing',
    );
  });

  testWidgets('a scope mounted under home does not reach one', (tester) async {
    final (device, client) = mountedDevice();
    final key = GlobalKey();

    // The shape this used to have: the scope around `home` rather than around
    // the Navigator.
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceScope(notifier: device, child: const SizedBox()),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaitedPush(navigator, key);
    await tester.pumpAndSettle();

    final reached = reachedFrom(key);
    await closeDevice(tester, device);

    expect(
      reached,
      isNull,
      reason: 'which is why every push had to re-provide it, and one did',
    );
  });
}

/// Pushes a bare route carrying [key], without awaiting the pop.
void unawaitedPush(NavigatorState navigator, GlobalKey key) {
  navigator.push(MaterialPageRoute<void>(builder: (_) => SizedBox(key: key)));
}
