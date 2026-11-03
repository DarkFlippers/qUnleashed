import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/pages/about/license_page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';

import 'firmware_fixture.dart';

/// When the licence is reflowed, and what the page draws when it cannot be
/// read.
///
/// `_normalize` splits the whole LICENSE and reassembles it through two
/// `StringBuffer`s, and it ran from `build` - for a string that arrives once
/// and never changes. `_load`'s own doc has why that survived #344 and what it
/// cost; #408 is the fix, and this file is what holds it.
///
/// **The witness is the identity of the string the page hands `SelectableText`,
/// and that is the whole trick here.** `out` takes a part per line, so its
/// `toString()` concatenates into a fresh string on every call: a reflow in
/// `build` cannot hand back the same instance twice, and a reflow in `_load`
/// can hand back nothing else. There is no counter to read and no seam worth
/// adding for one.
///
/// **Not because `toString()` always allocates** - it does not, and the
/// difference is the hole this witness has. `_StringBase._concatRange` returns
/// the single part unchanged when there is one, so an empty buffer and a
/// one-`write` buffer both hand back the identical instance on every call
/// (measured: `empty=true one=true oneLn=false many=false`). A `_normalize`
/// rewritten as one `write` into one buffer would therefore satisfy the
/// identity assertion while reflowing on every build, and only the first case
/// below would notice.
///
/// Two things keep that from passing for the wrong reason, and both are
/// asserted rather than assumed. The page must really have rebuilt - a theme
/// change is the stimulus, and `QPageAppBar` is the witness, since the page
/// constructs one per `build`; `test/device_scope_client_of_test.dart` uses
/// the same witness on the same page and records why the body cannot serve as
/// one. And it must not have been **remounted**, which
/// would reload the asset and produce a fresh string for a reason that has
/// nothing to do with where the reflow runs: the `State` is read back and
/// compared.
///
/// `rootBundle` answers `LICENSE` under `flutter_test` - the whole real GPL,
/// measured - so these cases run against the asset the app ships rather than a
/// fixture. Nothing here asserts its length or its line count, deliberately:
/// the first case compares the reflowed text against the raw text it just
/// read, so it says what it means on whatever `LICENSE` becomes.
///
/// ## Three mutations, three caught
///
/// | mutation | caught by |
/// |---|---|
/// | the reflow moves back into `build` - #408's own defect | reflows it once |
/// | `_normalize` returns its argument | reflows the licence |
/// | a failed load sets `_text`, not `_error` | shows the failure |
///
/// The second row is why the first case exists, measured rather than argued -
/// the case itself says how.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  // `rootBundle` is a `CachingAssetBundle` and a process-wide one, and
  // `loadString` caches the **future** rather than the string. So the entry a
  // case leaves behind was created inside that case's async zone and never
  // delivers in another one: measured with this line commented out, both
  // later cases fail with `pumpAndSettle timed out` - the page sits on its
  // forever-animating spinner - rather than quietly reading a licence from the
  // cache. Fail-safe either way, which is the point: what this buys is
  // order-independence, not protection from a false pass.
  setUp(rootBundle.clear);

  /// The page under a theme built from [seed].
  ///
  /// Composed from `wrapWithDevice` rather than written out, the way
  /// `device_scope_client_of_test.dart`'s own `tree` is: the fixture carries
  /// the argument for mounting `DeviceScope` through `builder` instead of
  /// around `home` (ADR 0011), and a copy of that here would go on testing a
  /// tree the app does not have the day the app moves the scope. The theme is
  /// this file's stimulus, so the fixture takes the seed.
  Widget tree(DeviceController device, Color seed) =>
      wrapWithDevice(const AppLicensePage(), device, seed: seed);

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
    // `identical` and not `same(before)`: on a failure the matcher
    // pretty-prints the expected operand and `expect`'s own formatter prints
    // the actual, neither truncates a `String`, and both are the whole licence
    // - 35 KB of GPL in the log, with the one fact that matters nowhere in
    // it.
    expect(
      identical(after, before),
      isTrue,
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
    //
    // It blanks the **whole** bundle rather than `LICENSE` alone - a mock
    // handler has no way to pass the other keys through to the real one - so
    // the app bar's icons fail with it. Harmless and checked: nothing records
    // an icon failure in this case, and `flutter_test_config.dart` rewinds
    // that static per test anyway.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async => null);
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final (device, _) = mountedDevice();

    await tester.pumpWidget(tree(device, const Color(0xFFCC241D)));
    await tester.pumpAndSettle();

    final drawn = drawnText(tester);
    final found = find.textContaining('Unable to load asset').evaluate().length;
    await closeDevice(tester, device);

    // Two assertions and not three: `_buildBody` is one if/return chain and
    // nothing else in this tree draws either widget, so the error text being
    // on screen already says the spinner is not. The second line is the other
    // half of this case's name rather than a third fact.
    expect(found, 1, reason: 'the failure was not reported on the page');
    expect(
      drawn,
      isNull,
      reason: 'a licence was drawn although none could be read',
    );
  });
}
