import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';

import 'firmware_fixture.dart';

/// That a pushed route can reach the device — ADR 0011.
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// The controller found at [key]'s context, or null if there is no scope.
  DeviceController? reachedFrom(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    return context.dependOnInheritedWidgetOfExactType<DeviceScope>()?.notifier;
  }

  testWidgets('a route pushed over the app is inside the scope', (
    tester,
  ) async {
    final (device, _) = mountedDevice();
    final key = GlobalKey();

    await tester.pumpWidget(QUnleashedApp(device: device));
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaitedPush(navigator, key);
    await tester.pumpAndSettle();

    expect(
      reachedFrom(key),
      same(device),
      reason: 'the same controller the shell reads, not a second one',
    );
  });

  testWidgets('a scope mounted under home does not reach one', (tester) async {
    final (device, _) = mountedDevice();
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

    expect(
      reachedFrom(key),
      isNull,
      reason: 'which is why every push had to re-provide it, and one did',
    );
  });
}

/// Pushes a bare route carrying [key], without awaiting the pop.
void unawaitedPush(NavigatorState navigator, GlobalKey key) {
  navigator.push(MaterialPageRoute<void>(builder: (_) => SizedBox(key: key)));
}
