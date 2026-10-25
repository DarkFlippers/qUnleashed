import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/pages/about/license_page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';

import 'firmware_fixture.dart';

/// What `DeviceScope.clientOf` does, and what it deliberately does not do.
///
/// `test/device_scope_listen_test.dart` is the ratchet that keeps the 30
/// client-only reads off `of`; this is the behaviour that makes moving them
/// worth doing, and the one consequence of the move that is a real difference
/// rather than a saving.
///
/// Every case here asserts a **pair**, because "nothing rebuilt" also passes
/// when the notification never arrived. The witness is [DeviceScopeProbe] -
/// see its doc for why the control cannot be the subject.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// How often a widget depending on the scope has rebuilt.
  var listeningBuilds = 0;

  /// Every client [_ClientReader] has been handed, in order.
  final read = <FlipperClient>[];

  setUp(() {
    resetFirmwareState();
    listeningBuilds = 0;
    read.clear();
  });

  /// A tree holding [child], the listening witness and a `clientOf` reader.
  ///
  /// `Stack` rather than a `Column`, so nothing here depends on the children
  /// fitting the test viewport.
  Widget tree(DeviceController device, {Widget child = const SizedBox()}) =>
      wrapWithDevice(
        Stack(
          children: [
            child,
            DeviceScopeProbe(onBuild: () => listeningBuilds++),
            _ClientReader(onRead: read.add),
          ],
        ),
        device,
      );

  testWidgets("hands back the controller's own client", (tester) async {
    final (device, client) = mountedDevice();

    await tester.pumpWidget(tree(device));
    await tester.pump();

    expect(read, hasLength(1));
    expect(
      read.single,
      same(client),
      // Not just "a client": the point of reading the tree rather than
      // `FlipperOneClient().get()` is that a test can mount a fake, and a
      // `clientOf` that resolved the global instead would pass a weaker check.
      // `test/client_reach_budget_test.dart` budgets `pages/devices` at zero,
      // so the sneakier `?? FlipperOneClient().get()` fallback dies there.
      reason: 'the one the scope was built with, not one resolved globally',
    );

    await closeDevice(tester, device);
  });

  testWidgets('does not rebuild its reader when the device notifies', (
    tester,
  ) async {
    final (device, client) = mountedDevice();

    await tester.pumpWidget(tree(device));
    await tester.pump();

    final listeningBefore = listeningBuilds;
    final readBefore = read.length;

    client.arrive(); // the poll's stand-in; see `FakeFlipperClient.arrive`.
    await tester.pumpAndSettle();

    expect(
      listeningBuilds,
      greaterThan(listeningBefore),
      reason:
          'the notification reached the scope, so the next line is a '
          'property of clientOf rather than of a notification that never came',
    );
    expect(read, hasLength(readBefore));

    await closeDevice(tester, device);
  });

  testWidgets('so the license page survives the device-info poll', (
    tester,
  ) async {
    // The sharpest of the 30. The read was in this page's `build`, so a poll
    // rebuilt the page - and `_normalize` splits and reassembles the whole
    // LICENSE text on the way through. Twelve times a minute, for a page whose
    // content never changes. #344.
    final (device, client) = mountedDevice();

    await tester.pumpWidget(tree(device, child: const AppLicensePage()));
    await tester.pumpAndSettle();

    // The bar stands in for the page's `build`: it is a widget instance the
    // page creates, so a rebuilt page is a different one. The body cannot be
    // used for this - whether `rootBundle` answers `LICENSE` under
    // `flutter_test` decides which branch of `_buildBody` is on screen, and
    // the bar is outside that choice.
    //
    // This case and the one above are not the same test twice. That one pins
    // the property of `clientOf` on a reader of this file's own; this one pins
    // it on one of the 30 real sites, and it is the only assertion here that
    // would catch `license_page.dart` re-acquiring a dependency by a route the
    // syntax ratchet cannot see - a controller taken into a local, or a read
    // moved into a helper.
    final barBefore = tester.widget<QPageAppBar>(find.byType(QPageAppBar));
    final listeningBefore = listeningBuilds;

    client.arrive();
    await tester.pumpAndSettle();

    expect(listeningBuilds, greaterThan(listeningBefore));
    expect(
      tester.widget<QPageAppBar>(find.byType(QPageAppBar)),
      same(barBefore),
      reason: 'the page rebuilt, which is what the scope read used to cost it',
    );

    await closeDevice(tester, device);
  });

  testWidgets('reads a replaced scope on the next build, not on the swap', (
    tester,
  ) async {
    // The one real consequence, pinned rather than left in a doc comment: no
    // dependency means no rebuild when the *widget* is replaced either, so a
    // reader holds the old client until something else rebuilds it.
    //
    // It cannot happen in the app as it stands - `_QUnleashedAppState._device`
    // is `late final`, so the notifier is one object for the run, which is
    // half of why `clientOf` is sound at all. This case exists so that a
    // change making the controller swappable fails here instead of shipping
    // stale clients to 30 call sites.
    final (first, firstClient) = mountedDevice();
    final (second, secondClient) = mountedDevice();
    final key = GlobalKey();

    // The scope on its own, and **one** reader widget instance across both
    // pumps. No `MaterialApp`: replacing one replaces every widget beneath it,
    // and `Element.updateChild` rebuilds a child whose widget is a new
    // instance whatever that child depends on - so the first draft of this
    // case measured the pump rather than the dependency, and saw a second
    // read on a reader nothing had notified. `updateChild` skips a child whose
    // widget is the *identical* instance, which is what leaves the
    // notification as the only thing that could rebuild it.
    final reader = _ClientReader(key: key, onRead: read.add);
    Widget framed(DeviceController device) =>
        DeviceScope(notifier: device, child: reader);

    await tester.pumpWidget(framed(first));
    await tester.pump();
    expect(read, [same(firstClient)]);

    await tester.pumpWidget(framed(second));
    await tester.pump();
    expect(
      read,
      hasLength(1),
      reason: 'a swapped scope does not rebuild a clientOf reader',
    );

    // Anything that rebuilds it reads the current scope correctly, which is
    // the half of the trade-off that makes it a delay rather than a bug - and
    // which kills a `clientOf` that cached what it found.
    tester.state<_ClientReaderState>(find.byKey(key)).rebuild();
    await tester.pump();
    expect(read, [same(firstClient), same(secondClient)]);

    await closeDevice(tester, first);
    await closeDevice(tester, second);
  });
}

/// A widget that reads the client the non-listening way, and reports each read.
///
/// Stateful so a case can rebuild it on demand without replacing the scope
/// above it.
class _ClientReader extends StatefulWidget {
  const _ClientReader({super.key, required this.onRead});

  final void Function(FlipperClient) onRead;

  @override
  State<_ClientReader> createState() => _ClientReaderState();
}

class _ClientReaderState extends State<_ClientReader> {
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    widget.onRead(DeviceScope.clientOf(context));
    return const SizedBox.shrink();
  }
}
