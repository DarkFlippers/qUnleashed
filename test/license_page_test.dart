import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/pages/about/license_page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';
import 'package:qunleashed/theme/theme.dart';

import 'firmware_fixture.dart';

/// When the licence is reflowed, and what the page draws when it cannot be
/// read.
///
/// `_normalize` splits all 674 lines of the LICENSE and reassembles them
/// through two `StringBuffer`s. It ran from `build`, for a string that arrives
/// once and never changes - so every rebuild paid for it again. #344 cut the
/// *rate* by taking the five-second device-info poll off this page, and
/// `test/device_scope_client_of_test.dart` has the case pinning that; #408 is
/// the work itself, on every rebuild that is left.
///
/// **The witness is the identity of the string the page hands `SelectableText`,
/// and that is the whole trick here.** `StringBuffer.toString()` builds a new
/// instance every time, so a reflow in `build` cannot hand back the same one
/// twice; a reflow in `_load` can hand back nothing else. There is no counter
/// to read and no seam worth adding for one.
///
/// Two things keep that from passing for the wrong reason, and both are
/// asserted rather than assumed. The page must really have rebuilt - a theme
/// change is the stimulus, and `QPageAppBar` is the witness, since the page
/// constructs one per `build`. And it must not have been **remounted**, which
/// would reload the asset and produce a fresh string for a reason that has
/// nothing to do with where the reflow runs: the `State` is read back and
/// compared.
///
/// `rootBundle` answers `LICENSE` under `flutter_test` - 35 149 characters of
/// the real GPL, measured - so these cases run against the asset the app
/// ships rather than a fixture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  // `rootBundle` is a `CachingAssetBundle` and a process-wide one: a case that
  // loads the real licence leaves it in `_stringCache`, where the failure case
  // below would find it and never reach its mock. Cleared before every case so
  // the order of the file does not decide what it tests.
  setUp(rootBundle.clear);

  /// The page under a theme built from [seed].
  ///
  /// `wrapWithDevice` is not used, although this is the tree it builds: the
  /// theme is the stimulus here, so it has to be a parameter. Everything else
  /// matches it, including `DeviceScope` through `builder` rather than around
  /// `home` - `QPageAppBar` reads the client through the scope, so the page
  /// does not build without one (ADR 0011).
  Widget tree(DeviceController device, Color seed) => MaterialApp(
    theme: buildAppTheme(Brightness.dark, seed),
    builder: (context, navigator) =>
        DeviceScope(notifier: device, child: navigator!),
    home: const AppLicensePage(),
  );

  /// The text the page is drawing, or null while it has none.
  String? drawnText(WidgetTester tester) {
    final found = find.byType(SelectableText);
    if (found.evaluate().isEmpty) return null;
    return tester.widget<SelectableText>(found).data;
  }

  testWidgets('reflows the licence it loaded', (tester) async {
    final (device, _) = mountedDevice();

    await tester.pumpWidget(tree(device, const Color(0xFFCC241D)));
    await tester.pumpAndSettle();

    final drawn = drawnText(tester);
    final raw = await rootBundle.loadString('LICENSE');
    await closeDevice(tester, device);

    expect(drawn, isNotNull, reason: 'the page never got past its spinner');
    // The reflow joins the licence's hard-wrapped paragraph lines, so the
    // rendered text is shorter in lines than the file. Asserted because the
    // identity case below would also pass on a `_normalize` that returned its
    // argument - and would then be pinning nothing at all.
    expect(
      drawn!.split('\n').length,
      lessThan(raw.split('\n').length),
      reason: 'nothing was reflowed, so the case below has no subject',
    );
    expect(
      drawn,
      contains('GNU GENERAL PUBLIC LICENSE'),
      reason: 'the page is drawing something other than the licence',
    );
  });

  testWidgets('reflows it once, not again on every build', (tester) async {
    final (device, _) = mountedDevice();

    await tester.pumpWidget(tree(device, const Color(0xFFCC241D)));
    await tester.pumpAndSettle();

    final before = drawnText(tester);
    final stateBefore = tester.state<State>(find.byType(AppLicensePage));
    final barBefore = tester.widget<QPageAppBar>(find.byType(QPageAppBar));
    expect(before, isNotNull, reason: 'the page never got past its spinner');

    // A theme change is one of the rebuilds #408 is about - the others are a
    // locale change and a `MaterialApp` rebuild from either. It reaches the
    // page through `context.appColors`, which is `Theme.of(this)`, so the page
    // rebuilds as a dependent even though its own widget is `const` and the
    // framework therefore never updates it from above.
    await tester.pumpWidget(tree(device, const Color(0xFF458588)));
    await tester.pumpAndSettle();

    final after = drawnText(tester);
    final stateAfter = tester.state<State>(find.byType(AppLicensePage));
    final barAfter = tester.widget<QPageAppBar>(find.byType(QPageAppBar));
    await closeDevice(tester, device);

    expect(
      barAfter,
      isNot(same(barBefore)),
      reason: 'the page did not rebuild, so the next line proves nothing',
    );
    expect(
      stateAfter,
      same(stateBefore),
      reason:
          'the page was remounted rather than rebuilt, so a fresh string is '
          'a reloaded asset and not a second reflow',
    );
    expect(
      after,
      same(before),
      reason:
          'a new string means `_normalize` ran again - 674 lines split and '
          'reassembled for a licence that cannot change',
    );
  });

  testWidgets('shows the failure rather than an empty licence', (tester) async {
    // The one thing moving the reflow could have broken: `_buildBody` branches
    // on `_error` first and on `_text == null` second, so a `catch` that wrote
    // a normalised `''` into `_text` instead of setting `_error` would swap the
    // error view for a blank page - and a reader would be told nothing at all.
    //
    // Driven at the asset channel, because the page reaches `rootBundle`
    // directly. A null reply is what `PlatformAssetBundle` turns into its
    // "Unable to load asset" throw, which is the real failure here: a build
    // whose assets did not ship.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async => null);
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final (device, _) = mountedDevice();

    await tester.pumpWidget(tree(device, const Color(0xFFCC241D)));
    await tester.pumpAndSettle();

    final drawn = drawnText(tester);
    final spinners = find.byType(CircularProgressIndicator).evaluate().length;
    final message = find.textContaining('Unable to load asset');
    final found = message.evaluate().length;
    await closeDevice(tester, device);

    expect(found, 1, reason: 'the failure was not reported on the page');
    expect(spinners, 0, reason: 'the page is still showing its spinner');
    expect(
      drawn,
      isNull,
      reason: 'a licence was drawn although none could be read',
    );
  });
}
