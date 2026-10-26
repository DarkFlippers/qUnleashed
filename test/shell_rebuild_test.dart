import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/app/nav_bar.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/pages/archive/overview/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/telemetry/settings.dart';

import 'firmware_fixture.dart';

/// What a notification is allowed to rebuild in the shell, and what it is not.
///
/// Two sources reach it and both used to rebuild everything: the five-second
/// device-info poll (#407) and archive activity (#410). The poll cases fire
/// `setRecovering`; the archive case fires `notifyListeners` on the
/// controller. 'the visible slot survives a layout flip' fires neither — it
/// covers the locals the #407 hoist created, which a layout flip is what
/// moves.
///
/// `AppShell` holds the whole app: a `FlipperRootScaffold` whose `child` is an
/// `IndexedStack` carrying every tab the user has visited, all of them still
/// mounted. The only thing in there that depends on either controller is
/// `deviceLabel` — one string in the bottom bar, read from the device's
/// `connectionState`, `device`, `deviceLoading` and `deviceInfoConnected` and,
/// in the `connected` case alone, the archive's `syncStatus` — and the **wide
/// layout does not draw even that**: `FlipperRootScaffold.build` ignores
/// `deviceLabel` entirely when `isWide`, so on a desktop window nothing
/// inside the notification-dependent region displays a value either
/// controller can change.
///
/// The two sources are not symmetric any more, and the archive case turns on
/// it. The shell listens to the **whole** device controller, so a poll tick
/// rebuilds the nav bar; it listens only to `ArchiveController.syncStatus`, a
/// `ValueNotifier`, so an archive notification rebuilds nothing of the
/// shell's at all.
///
/// Two things used to make a tick rebuild all of it, and both are needed:
///
///  * `_AppShellState.build` read the scope with the listening `DeviceScope.of`,
///    which subscribed the shell's own element — so the `ListenableBuilder`
///    below that read narrowed nothing, because the thing it was meant to
///    protect was being rebuilt from above it. `DeviceScope.notifierOf` keeps
///    the tick out of `_AppShellState.build`.
///  * the `IndexedStack` was constructed *inside* that builder, so even a
///    rebuild starting at the builder produced a new instance and re-ran every
///    mounted page's `build`. It is passed through `ListenableBuilder.child`
///    now, and `Element.updateChild` skips a child whose widget is the
///    identical instance.
///
/// **The witness is widget identity, not a scroll position**, and the first
/// draft got that wrong. A rebuilt `IndexedStack` *updates* its children
/// rather than tearing them down — `State` objects and scroll controllers
/// survive — so the cost is every page's `build` running twelve times a
/// minute, which a scroll offset cannot see. What identity sees is exactly the
/// mechanism: the same instance went through untouched, or a new one did not.
///
/// What identity *separates* is the hoisting, not `ListenableBuilder.child`
/// specifically — a builder closing over the hoisted `pages` local instead of
/// taking the `child` parameter hands back the same instance and passes every
/// case here. The `child:` form is the idiomatic spelling of the hoist, not a
/// second mechanism.
///
/// And these cases are not the only net under the `of` regression:
/// `test/device_scope_listen_test.dart` fails twice over if a listening read
/// comes back to `lib/app/` — the listening census reports `app: 1, up from
/// 0`, and the `notifierOf` census fails its per-area check with "no read
/// found in app at all". That matters, because the `railGroups` witness below
/// is defeated by memoising `_railGroups`, which is a plausible next
/// optimisation; the ratchet is what survives that.
///
/// **The tick is `setRecovering`, not a connection event**, and that is the
/// second thing the first draft got wrong. `FakeFlipperClient.arrive()` puts
/// an event on `connectionStream` and **both controllers are subscribed to
/// it**: `ArchiveController._onConnectionChange` notifies on every event, and
/// `DeviceController._onConnectionState` on every event that is not
/// `connecting`. So `arrive()`'s event reaches both, and a case built on a
/// rebuild or an identity witness cannot say which source the shell answered.
///
/// A case built on a *value* witness could — the value is the claim, whatever
/// fired. None here is, and the note at the foot of this file says why the one
/// that wants to be cannot.
///
/// When the first draft ran, the archive side of that was a whole-shell
/// `setState` in `_AppShellState._onArchiveChanged`, so the device cases
/// failed outright. #410 removed that listener, which is why the last two
/// cases exist.
///
/// So the device cases fire `setRecovering`, which notifies the device
/// controller alone, and the archive cases fire `notifyListeners()` on the
/// controller itself.
///
/// Not `setDfuPresent` for the device half, which was the second attempt: the
/// controller subscribes `DfuDetector.presence` to it, and the detector's
/// one-second poll runs inside `pumpAndSettle` and pushes `false` straight
/// back - so the label returned to its old value and the assertion on it
/// failed for a reason that had nothing to do with the shell. `setRecovering`
/// also stops that detector, and `connectionState` checks `_recovering`
/// first. #407.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// The app at [size], with a real controller, settled.
  ///
  /// The narrow cases use 360, the common Android baseline. They ran at 500
  /// until #411, because the device page's own header overflowed its `Row`
  /// below about 400 and `flutter_test` turns a layout overflow into a
  /// failure - so this file was failing on a bug of someone else's and the
  /// width was raised rather than the bug papered over. The header carries a
  /// flex factor now and `test/device_header_fit_test.dart` holds it to every
  /// phone width in every locale; this is the whole-app half of that.
  ///
  /// **The window is sized through `tester.view`, not `setSurfaceSize`**, and
  /// this file used the latter until #410. `setSurfaceSize` overrides the
  /// render view's configuration and nothing else: `MediaQuery` is built from
  /// `View.of(context)`, so it kept answering the default 800x600 - which
  /// `FlipperRootScaffold.isWide` reads, and 800 by 600 is wide. Every case
  /// here ran on the desktop rail, the one named for a narrow window and the
  /// layout flip included. `_surfaceSize` feeds only
  /// `createViewConfigurationFor`, which is the mechanism; the framework's doc
  /// recommends `TestFlutterView.physicalSize` instead, and four other files
  /// here already use it.
  ///
  /// So the three cases below named for a narrow window are **new coverage**,
  /// not coverage this change preserved. They pass, including through the
  /// device page's own narrow branch, which #411 lives in.
  ///
  /// `devicePixelRatio` is pinned to 1 so [size] is read in logical pixels -
  /// the test binding's default is 3, which would make 360 a 120dp window.
  Future<(DeviceController, FakeFlipperClient)> pumpApp(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (device, client) = mountedDevice();
    await tester.pumpWidget(
      QUnleashedApp(
        client: client,
        diagnostics: DiagnosticsSettings(),
        permissions: PermissionCenter(),
        device: device,
      ),
    );
    await tester.pumpAndSettle();
    return (device, client);
  }

  /// The shell's page stack — the outermost [IndexedStack], which is the one
  /// `FlipperRootScaffold` is handed as its `child`.
  ///
  /// `find.byType` walks in tree order, so `.first` is the outermost; a page
  /// with an `IndexedStack` of its own cannot be mistaken for it. Asserted on
  /// rather than assumed, because "the first one" is a fact about the tree
  /// that a layout change could quietly alter.
  IndexedStack pageStack(WidgetTester tester) {
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack).first);
    expect(
      stack.children,
      hasLength(greaterThan(4)),
      reason: 'expected the shell stack with a slot per tab, not a page',
    );
    return stack;
  }

  FlipperRootScaffold scaffoldIn(WidgetTester tester) =>
      tester.widget<FlipperRootScaffold>(find.byType(FlipperRootScaffold));

  /// How many rail destinations are drawn as selected.
  ///
  /// `_railItem` sets `selected` from `slot == target`, so this is the rail's
  /// view of which slot is current. Exactly one, always - and it is a second
  /// witness on the same `slot` local the stack's index comes from, which is
  /// what catches `_railGroups(colors, _slot)`: on a wide layout with the
  /// archive slot selected, no rail destination matches it at all.
  int selectedRailItems(WidgetTester tester) =>
      scaffoldIn(tester).railGroups
          .expand((group) => group)
          .where((item) => item.selected)
          .length;

  /// Whether the slot the stack is showing draws anything.
  ///
  /// `_page` answers `SizedBox.shrink()` for a slot that does not belong to
  /// the current layout, so an index pointing at one is a blank pane. Asserted
  /// as the symptom rather than against a private slot constant.
  bool visibleSlotIsDrawn(WidgetTester tester) {
    final stack = pageStack(tester);
    final index = stack.index;
    expect(index, isNotNull, reason: 'the shell always selects a slot');
    return stack.children[index!] is! SizedBox;
  }

  /// The archive controller the shell built, taken back out of the tree.
  ///
  /// `_AppShellState` constructs it from `widget.client` and keeps it private,
  /// so there is no seam to reach it through - but it hands the same instance
  /// to every archive page, and the overview slot is in `_mounted` from the
  /// first frame on a narrow layout. Reading it back costs the production
  /// code nothing, which a constructor parameter added for this would not.
  ///
  /// Narrow only, and **only once the archive tab is the selected one**:
  /// `_page` blanks the overview slot when `wide`, and `find.byType` skips
  /// offstage widgets - a non-selected `IndexedStack` child is offstage, so
  /// the page is mounted but not found. Both archive cases select the tab
  /// first, which is also the situation they are about: somebody watching the
  /// archive screen while a sync runs.
  ArchiveController archiveIn(WidgetTester tester) =>
      tester.widget<ArchivePage>(find.byType(ArchivePage)).controller;

  /// The `Scaffold` the overview page's own `AnimatedBuilder` returns.
  ///
  /// Scoped to inside [ArchivePage], so the shell's own scaffold cannot be
  /// mistaken for it. Not `.first`: the page builds exactly one `Scaffold`, so
  /// a bare `tester.widget` throws the day the subtree gains a second rather
  /// than quietly taking the outer one.
  Scaffold archivePageBody(WidgetTester tester) => tester.widget<Scaffold>(
    find.descendant(
      of: find.byType(ArchivePage),
      matching: find.byType(Scaffold),
    ),
  );

  /// Puts the archive overview on screen and settles.
  ///
  /// `pumpAndSettle` is safe here only because the controller is idle: the
  /// sync bar's indeterminate `CircularProgressIndicator` is not mounted, so
  /// there is no animation to wait out. A case that put the controller into
  /// `syncing` - the one the note at the foot of this file wants - would hang
  /// instead, and `settle()` in `archive_fakes.dart` is the existing answer.
  Future<void> showArchive(WidgetTester tester) async {
    scaffoldIn(tester).onTabSelected(FlipperRootTab.archive);
    await tester.pumpAndSettle();
  }

  testWidgets('a poll tick rebuilds the nav bar and not the page stack', (
    tester,
  ) async {
    final (device, _) = await pumpApp(tester, const Size(360, 900));

    final stackBefore = pageStack(tester);
    final labelBefore = scaffoldIn(tester).deviceLabel;

    // A notification from the scope and from nothing else - see the note on
    // `setRecovering` above. It also moves `connectionState` to `recovering`,
    // so the label the scaffold carries really does change.
    device.setRecovering(true);
    await tester.pumpAndSettle();

    // A pair, because "nothing rebuilt" also passes when the notification
    // never arrived. **The control is the label's value, not the scaffold's
    // identity.** The builder constructs a new `FlipperRootScaffold` whenever
    // it runs, so an `isNot(same(...))` control is satisfied by the plumbing
    // rather than by anything the tick achieved - the first draft used
    // identity, and hoisting `_deviceLabel(device)` out of the builder beside
    // `railGroups`, which freezes the bottom bar at whatever the state was
    // when the shell last built, passed all 33 cases. Nothing else in the
    // suite asserts that string.
    expect(
      scaffoldIn(tester).deviceLabel,
      isNot(labelBefore),
      reason:
          'the label did not follow the device, so the line below would pass '
          'on a region that rebuilds and produces the same output - which is '
          'what hoisting _deviceLabel out of the builder costs',
    );
    expect(
      pageStack(tester),
      same(stackBefore),
      reason:
          'a new IndexedStack re-runs every mounted page build - which is '
          'what building it inside the ListenableBuilder costs on every tick',
    );

    await closeDevice(tester, device);
  });

  testWidgets('and the shell itself is not rebuilt by the tick', (
    tester,
  ) async {
    // The other half, asserted on its cause rather than on the same symptom:
    // `notifierOf` rather than `of`, so the subscription sits on the
    // `ListenableBuilder` and not on `_AppShellState`.
    //
    // **The witness is `railGroups`.** `_railGroups(colors, slot)` returns a
    // fresh list on every `_AppShellState.build`, and the builder below does not
    // call it — it closes over the result. So the same list instance means
    // the shell's own `build` did not re-run, and a new one means it did,
    // independently of the `child:` plumbing the case above tests.
    //
    // The first draft compared `ListenableBuilder` instances found with
    // `find.byType(...).first`, and two mutations walked straight through it:
    // making the shell's read listening again left it green. `.first` was
    // finding a builder from the framework's own tree, above the shell and
    // never rebuilt - a case that passed for a reason it was not about.
    final (device, _) = await pumpApp(tester, const Size(360, 900));

    final groupsBefore = scaffoldIn(tester).railGroups;
    final indexBefore = pageStack(tester).index;

    device.setRecovering(true);
    await tester.pumpAndSettle();

    expect(
      scaffoldIn(tester).railGroups,
      same(groupsBefore),
      reason:
          '_AppShellState.build re-ran, which is what a listening '
          'DeviceScope.of in it costs - and it makes the ListenableBuilder '
          'under it pointless',
    );

    // **The witness has to be alive, or it proves nothing.** A `_railGroups`
    // that memoised its result would satisfy the line above forever, whatever
    // the shell did - and memoising it is a plausible next optimisation, since
    // it depends only on `colors` and `slot`. So something that really does
    // rebuild the shell has to move the identity. A tab tap is that something,
    // and it pins the other half of the hoist at the same time: `currentTab`
    // moved out of the builder in this change, so a tap that no longer
    // switched tabs would be the regression nothing else here would catch.
    await showArchive(tester);

    expect(
      scaffoldIn(tester).currentTab,
      FlipperRootTab.archive,
      reason: 'the tab did not switch, so the rebuild below is not a tab tap',
    );
    expect(
      scaffoldIn(tester).railGroups,
      isNot(same(groupsBefore)),
      reason:
          'railGroups is the same list after a real shell rebuild, so it '
          'cannot witness the absence of one - it has been memoised',
    );
    expect(
      pageStack(tester).index,
      isNot(equals(indexBefore)),
      reason:
          'the stack still shows the old slot, so the hoisted index is not '
          'following the selection',
    );

    await closeDevice(tester, device);
  });

  testWidgets('the visible slot survives a layout flip', (tester) async {
    // **What the hoisted locals are computed *from*.** `slot` is
    // `_visibleSlot(wide)`, not `_slot`: wide turns the archive slot into
    // favourites and narrow turns an archive-detail slot back into archive,
    // because `_page` blanks a slot that does not belong to the current
    // layout. So `index: slot` and `railGroups(colors, slot)` are both
    // load-bearing, and `index: _slot` - a one-token slip the hoist newly
    // makes possible - is a blank content pane rather than a wrong tab.
    //
    // A review ran exactly that mutation against the whole suite and it was
    // green: nothing in `test/` read `IndexedStack.index`, and the liveness
    // check above only asked whether the rail list had changed. This case is
    // the net, and it asserts the symptom rather than a private slot number -
    // the pane the user is looking at is not empty.
    //
    // **And until #410 it was not a flip**, because `setSurfaceSize` left
    // `MediaQuery` at 800x600 and both sizes below read as wide. See `pumpApp`.
    final (device, _) = await pumpApp(tester, const Size(360, 900));

    await showArchive(tester);
    expect(visibleSlotIsDrawn(tester), isTrue, reason: 'blank while narrow');
    // Zero, and the narrow layout is right to show nothing: `_railGroups` has
    // no destination for the overview slot at all - the rail reaches the
    // archive through favourites, the categories and deleted, and the overview
    // is the bottom bar's entry point. So no rail item matches the current
    // slot, which is what the fallback below exists to fix.
    expect(
      selectedRailItems(tester),
      0,
      reason:
          'a rail destination matched the overview slot, so the wide '
          'fallback below is not the only thing lighting one',
    );

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();

    expect(
      visibleSlotIsDrawn(tester),
      isTrue,
      reason:
          'the archive slot is blanked on a wide layout, so the index has to '
          'fall back to favourites - a rail with an empty pane beside it',
    );
    expect(
      selectedRailItems(tester),
      1,
      reason:
          'the rail is lit from the same fallback, so no destination matches '
          'the raw slot on this layout - nothing is highlighted at all',
    );

    await closeDevice(tester, device);
  });

  testWidgets('on a wide window, where the label is not even drawn', (
    tester,
  ) async {
    // `FlipperRootScaffold.build` takes the `isWide` branch and never reads
    // `deviceLabel` - nor `currentTab`, nor `onTabSelected` - so on this
    // layout a tick rebuilt the scaffold for a value nothing displays. That
    // is what makes the stack surviving the only thing worth asserting here.
    //
    // Not because the stack is bigger: at first pump `_mounted` is
    // {device, archive, tools} and `_page` blanks the archive slot when wide,
    // so this layout has two real pages against the narrow layout's three.
    // The first draft claimed the opposite, and the claim was the reason the
    // case existed - the surviving reason is the first clause.
    final (device, _) = await pumpApp(tester, const Size(1200, 800));

    final stackBefore = pageStack(tester);
    final labelBefore = scaffoldIn(tester).deviceLabel;

    device.setRecovering(true);
    await tester.pumpAndSettle();

    // The same pair as the narrow case. `setRecovering` early-returns when
    // the flag already matches, so without a control this case would pass
    // having observed nothing - and read as green coverage of the layout
    // where the stack matters most. The label still changes here even though
    // this layout does not draw it.
    expect(scaffoldIn(tester).deviceLabel, isNot(labelBefore));
    expect(pageStack(tester), same(stackBefore));

    await closeDevice(tester, device);
  });

  testWidgets('an archive notification reaches the archive page and nothing '
      'else', (tester) async {
    // #410, and it is one case rather than two because every claim here is
    // that something did *not* rebuild - so without a control it would pass
    // just as well on a notification that never arrived, which is the trap
    // this file records at the device cases above.
    //
    // The control is the overview page's own body, and it earns its place
    // twice. It proves the notification reached the tree, and it answers the
    // risk the three claims create: if the pages leant on the shell's
    // `setState` to follow the controller, keeping the `IndexedStack`
    // identical would leave the archive screen stale and the saving would be
    // a bug. They do not lean on it - the four pages that take the controller
    // wrap their whole build in an `AnimatedBuilder` over it (`animation:
    // _ctrl` in the overview, `_repaint` in the three category pages) and not
    // one of them declares a `didUpdateWidget`, so nothing of theirs was ever
    // driven by its widget being replaced from above. #405 is where that came
    // from. `FileManagerPage` shares the stack but takes the client, not the
    // controller, so an archive notification never reached it either way.
    //
    // Only the overview is covered, because `archiveIn` is narrow-only and
    // the other three are the wide layout's. Their `_repaint` is exercised
    // page-level in `archive_bulk_outlives_page_test.dart` and
    // `archive_sort_page_test.dart`, so that is a composition gap rather than
    // an unguarded mechanism.
    final (device, _) = await pumpApp(tester, const Size(360, 900));
    await showArchive(tester);

    final archive = archiveIn(tester);
    final scaffoldBefore = scaffoldIn(tester);
    final groupsBefore = scaffoldBefore.railGroups;
    final stackBefore = pageStack(tester);
    final bodyBefore = archivePageBody(tester);

    // The stand-in for all forty-one of the controller's own notify sites -
    // `notifyListeners` is a public override on `ArchiveController`. Which
    // site produced it is the controller's business; what is pinned here is
    // what the shell does when one arrives.
    archive.notifyListeners();
    await tester.pumpAndSettle();

    expect(
      archivePageBody(tester),
      isNot(same(bodyBefore)),
      reason:
          'the overview page did not answer the notification on its own, so '
          'the three claims below are about a notification that arrived '
          'nowhere - and skipping the page stack would leave the archive '
          'screen drawing stale state',
    );
    expect(
      scaffoldIn(tester),
      same(scaffoldBefore),
      reason:
          'the nav bar was rebuilt for a notification it draws nothing from - '
          'the merge is listening to the whole controller rather than to its '
          'syncStatus notifier',
    );
    // Live only because of the tab tap in the second device case above: a
    // memoised `_railGroups` would satisfy this forever, and nothing in *this*
    // case would notice. Do not split that case away from this one.
    expect(
      scaffoldIn(tester).railGroups,
      same(groupsBefore),
      reason:
          '_AppShellState.build re-ran, which is what _onArchiveChanged cost '
          'on every notification',
    );
    expect(
      pageStack(tester),
      same(stackBefore),
      reason:
          'a new IndexedStack re-runs every mounted page build - four times '
          'per file a sync downloads',
    );

    await closeDevice(tester, device);
  });

  // **The missing witness, named rather than left to be discovered.**
  //
  // Nothing here - or anywhere in `test/` - asserts that `deviceLabel`
  // follows `ArchiveController.syncStatus`. That read is the whole reason the
  // sync status is in the merged listenable, so **three** mutations survive
  // the suite: dropping the `switch (_syncStatus)` from `_deviceLabel`'s
  // `connected` branch, `_syncStatus => ArchiveSyncStatus.idle`, and dropping
  // `_archiveController.syncStatus` from the merge altogether. Each leaves
  // the bottom bar not following a sync, which is the user-visible half of
  // #410.
  //
  // The third got easier to make, not harder, when the subscription narrowed
  // from the controller to its status notifier: the case above asserts that
  // an archive notification rebuilds *nothing* of the shell's, which a merge
  // listening to nothing archive-related satisfies perfectly. That is the
  // price of the narrowing and it is worth paying - but it is a price, and
  // this is where it is recorded.
  //
  // A fourth survives for the same reason, and it is the one that would undo
  // the saving silently: adding a `notifyListeners()` beside
  // `_syncStatusNotifier.value = status` in `ArchiveController`. The `!=`
  // dedup is the whole of "three rebuilds a sync rather than eight thousand",
  // and nothing here would notice it going.
  //
  // It is not reachable from this fixture, and the reason is specific rather
  // than a shrug. `_deviceLabel` consults `syncStatus` only when
  // `connectionState` is `connected`, which needs `DeviceController._device`
  // non-null - and `FakeFlipperClient.arrive()` carries `device: null` on
  // purpose, so `_onConnectionState` leaves it null. A fake that connected
  // would then have to reach a non-`idle` `syncStatus`, and every path that
  // sets `syncing` runs through `_client.runTask` into `storageList`,
  // `storageMd5sum` and `storageReadChunked`, none of which this fake
  // answers.
  //
  // So it wants a connected `FakeFlipperClient` with a storage API, which is
  // its own change - and the same one #407 wanted for `_openFullInfo`. Filed
  // rather than half-built.
}
