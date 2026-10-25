import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/components/appbar.dart';
import 'package:qunleashed/components/changelog_renderer.dart';
import 'package:qunleashed/pages/apps/catalog/controller.dart';
import 'package:qunleashed/pages/apps/catalog/detail_page.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/action_button.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/models/detail.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';

import 'firmware_fixture.dart';

/// What is allowed to rebuild the app detail page's body, and what is not.
///
/// The body carries up to three `SelectionArea`s over `flutter_html` - short
/// description, description, changelog, each shown only when its field is
/// non-empty. Rebuilding one costs the selection in any paragraph whose span
/// tree holds a `WidgetSpan`, which here is every block element: flutter_html
/// renders those as `WidgetSpan`s
/// (`builtins/styled_element_builtin.dart`), widget equality is identity, so
/// `WidgetSpan.compareTo` is `RenderComparison.layout`, and
/// `RenderParagraph`'s `text` setter answers a layout comparison by disposing
/// its selectable fragments and registering fresh ones
/// (`rendering/paragraph.dart`). An inline link is *not* one of these: it
/// stays a `TextSpan` carrying a fresh `TapGestureRecognizer`, which compares
/// as `metadata` and leaves the fragments alone.
///
/// The selection those fragments held is gone, so
/// `SelectionGeometry.endSelectionPoint` is null. The overlay's drag handles
/// belong to `SelectableRegionState` rather than to the paragraph, and it does
/// tear them down when the geometry empties - but from a listener, and the
/// geometry recompute is itself deferred, so there is a window where the
/// handles are live over an empty geometry. A drag update landing in it reads
/// `endSelectionPoint!` and throws from inside a gesture callback, which no
/// `try` on the page can see. QUNLEASHED-F.
///
/// The page used to hand both of its tickers the whole body: it read
/// `DeviceScope.of(context)` in its own `build`, and the scope notifies on the
/// device-info poll - `lib/services/connection/device_info_watch.dart`, every
/// five seconds while a Flipper is connected and idle - and it wrapped
/// everything in one `AnimatedBuilder` on the catalog controller, which
/// notifies per throttled progress step of an install. So the selection was
/// being thrown away every five seconds with a device attached, and several
/// times a second during an install.
///
/// Both cases below assert a pair, because "nothing rebuilt" also passes when
/// the notification never arrived: the renderers are the *same* instances
/// afterwards, and something that legitimately listens is *not*.
///
/// For the poll that something is [DeviceScopeProbe], a widget mounted under
/// the same scope, rather than the bar. The bar would do today, since it is
/// what reads the scope - but the page does not *need* that dependency (the
/// client it wants is one object for the tree's life, and `QPageAppBar`
/// subscribes to the device's streams itself), and
/// `firmware_changelog_page.dart` already takes its client as a parameter
/// instead. Were this page tightened the same way, a witness on the bar would
/// fail reading "the poll never arrived" on a page that had just got strictly
/// better. The probe asserts the invariant - the notification reached the
/// scope's dependents, and the body still did not rebuild - and survives that.
/// For install progress the witnesses are the two widgets the fix claims to
/// have kept listening: the install button and the bar's actions.
///
/// **That tightening happened, in #344**, and the choice above is why this
/// file needed no change for it: `_DetailAppBar` reads
/// `DeviceScope.clientOf` now, so nothing on this page depends on the scope at
/// all. The first case below still kills putting `of` back in
/// `_AppDetailPageState.build`, but it no longer distinguishes *the read stops
/// at the bar* from *the read registers no dependency* - it would pass for any
/// arrangement of the bar, including the inlining that `detail_page.dart` now
/// says would be safe. The second case is untouched: the `AnimatedBuilder` on
/// the catalog controller is still there, and still the only thing stopping
/// the delete action going stale.
///
/// What that pair shows is that nothing *above* the renderers rebuilt. It is
/// not proof that no descendant did, and no case here drives a selection or
/// the crash itself; the mechanism above is why the property is worth holding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// How often a widget depending on the scope has rebuilt - see
  /// [DeviceScopeProbe].
  ///
  /// Never reset: every assertion on it is a delta against a count taken in
  /// the case itself.
  var scopeBuilds = 0;

  // The only global state this tree needs. The firmware fixture's
  // `resetFirmwareState` would do it, along with seven things it does not.
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  /// A detail that fills all three fields, so all three renderers are on
  /// screen.
  ///
  /// Markdown with block elements - a heading and a list - since a block
  /// element is what flutter_html turns into the `WidgetSpan` that forces the
  /// layout comparison. No images: `Image.network` under `flutter_test` fails
  /// the load, and the point here is the rebuild, not the span inventory.
  AppDetail detailFixture() => AppDetail.fromJson(const {
    'id': 'test-app-uid',
    'alias': 'test-app',
    'category_id': 'Tools',
    'author': 'nobody',
    'current_version': {
      'id': 'test-version',
      'name': 'Test App',
      'version': '1.0',
      'short_description': 'A short description.',
      'changelog':
          '## 1.0\n\n- first line of the changelog\n- second line\n\n'
          'A closing paragraph.\n',
      'description': 'A longer description, in its own renderer.\n',
    },
  });

  /// The renderers currently mounted, by instance.
  ///
  /// `skipOffstage: false` because the body is a `ListView` whose content is
  /// taller than the test viewport by a margin small enough that a wording
  /// change in the fixture could push a renderer out of the paint extent. An
  /// offstage renderer would drop out of both snapshots, and its rebuild would
  /// go unseen.
  List<ChangelogRenderer> renderersIn(WidgetTester tester) => tester
      .widgetList<ChangelogRenderer>(
        find.byType(ChangelogRenderer, skipOffstage: false),
      )
      .toList(growable: false);

  Future<(_FixedDetailController, DeviceController, FakeFlipperClient)>
  pumpDetail(WidgetTester tester) async {
    final controller = _FixedDetailController(_FixedApi(detailFixture()));
    addTearDown(controller.dispose);
    final (device, client) = mountedDevice();

    await tester.pumpWidget(
      wrapWithDevice(
        Stack(
          children: [
            AppDetailPage(alias: 'test-app', controller: controller),
            DeviceScopeProbe(onBuild: () => scopeBuilds++),
          ],
        ),
        device,
      ),
    );
    await tester.pumpAndSettle();

    // All three of the fixture's fields are non-empty, so all three renderers
    // are up. Asserted rather than assumed, since the file reasons about how
    // many there are.
    expect(renderersIn(tester), hasLength(3));
    return (controller, device, client);
  }

  AppActionButton buttonIn(WidgetTester tester) =>
      tester.widget<AppActionButton>(find.byType(AppActionButton));

  QPageAppBar barIn(WidgetTester tester) =>
      tester.widget<QPageAppBar>(find.byType(QPageAppBar));

  testWidgets('a device notification does not rebuild the changelog', (
    tester,
  ) async {
    final (_, device, client) = await pumpDetail(tester);

    final before = renderersIn(tester);
    final probeBefore = scopeBuilds;

    client.arrive(); // the poll's stand-in; see `FakeFlipperClient.arrive`.
    await tester.pumpAndSettle();

    // It reached the scope's dependents, so "nothing rebuilt" below is the
    // page's doing rather than a notification that never arrived.
    expect(scopeBuilds, greaterThan(probeBefore));
    expect(renderersIn(tester), orderedEquals(before));

    await closeDevice(tester, device);
  });

  testWidgets('install progress does not rebuild the changelog', (
    tester,
  ) async {
    final (controller, device, _) = await pumpDetail(tester);

    final before = renderersIn(tester);
    final buttonBefore = buttonIn(tester);
    final barBefore = barIn(tester);

    controller.bump();
    await tester.pump();

    // Both widgets the fix kept listening. The bar matters on its own: without
    // its `AnimatedBuilder` the delete action goes stale - it would stop
    // appearing after an install and stop going away after a delete - and
    // nothing else here would notice.
    expect(buttonIn(tester), isNot(same(buttonBefore)));
    expect(barIn(tester), isNot(same(barBefore)));
    expect(renderersIn(tester), orderedEquals(before));

    await closeDevice(tester, device);
  });
}

/// An API that answers `fetchApp` without a network, so the page renders its
/// body rather than its error view.
class _FixedApi extends AppsCatalogApi {
  _FixedApi(this.detail);

  final AppDetail detail;

  @override
  Future<AppDetail> fetchApp(
    String idOrAlias, {
    bool? isLatestReleaseVersion,
  }) async => detail;
}

/// The real controller with `fetchApp` replaced, and a way to make it notify
/// the way an install's progress does.
///
/// Only `fetchApp` is replaced. `engine`, `manifests` and so `isInstalled` and
/// `stateFor` are the real process-wide singletons behind
/// `AppsBackend.instance`, which nothing here resets - fine while the cases
/// only read them, worth knowing before adding one that drives an install.
/// `initialize()` is never called, which is the only reason the controller
/// stays off the network.
///
/// A bare `notifyListeners` stands in for a progress step because the
/// forwarding is unfiltered: `AppsCatalogController` wires
/// `engine.addListener(notifyListeners)`, so every `_setActionState` the
/// throttle lets through arrives here unchanged.
class _FixedDetailController extends AppsCatalogController {
  _FixedDetailController(this._api);

  final AppsCatalogApi _api;

  @override
  AppsCatalogApi get api => _api;

  void bump() => notifyListeners();
}
