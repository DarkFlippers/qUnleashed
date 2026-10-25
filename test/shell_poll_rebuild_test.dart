import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/app/nav_bar.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/telemetry/settings.dart';

import 'firmware_fixture.dart';

/// What a device-info poll tick is allowed to rebuild in the shell, and what
/// it is not.
///
/// `AppShell` holds the whole app: a `FlipperRootScaffold` whose `child` is an
/// `IndexedStack` carrying every tab the user has visited, all of them still
/// mounted. The only thing in there that depends on the device is
/// `deviceLabel` — one string in the bottom bar — and the **wide layout does
/// not draw even that**: `FlipperRootScaffold.build` ignores `deviceLabel`
/// entirely when `isWide`, so on a desktop window nothing inside the
/// device-dependent region displays a device-dependent value at all.
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
/// an event on `connectionStream`, which `ArchiveController` is also
/// subscribed to (`archive/overview/controller.dart`) — and `_AppShellState`
/// holds `_archiveController.addListener(_onArchiveChanged)`, whose body is an
/// unconditional `setState`. So a connection event rebuilds the whole shell
/// through a path that has nothing to do with `DeviceScope`, and the cases
/// below would have failed for a reason they were not about. #410 is that
/// listener.
///
/// `setRecovering` notifies the device controller and nothing else, which is
/// the notification this change is about. Not `setDfuPresent`, which was the
/// second attempt: the controller subscribes `DfuDetector.presence` to it, and
/// the detector's one-second poll runs inside `pumpAndSettle` and pushes
/// `false` straight back - so the label returned to its old value and the
/// assertion on it failed for a reason that had nothing to do with the shell.
/// `setRecovering` also stops that detector, and `connectionState` checks
/// `_recovering` first. #407.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// The app at [size], with a real controller, settled.
  ///
  /// The narrow cases use 500 and not a more typical phone width, because at
  /// 420 the device page's own header overflows its `Row` by 41 pixels and
  /// `flutter_test` turns that into a failure - with default English strings,
  /// so it is the base case rather than a long translation. That is a real bug
  /// and it is not this one, so it is filed as #411 rather than worked
  /// around silently; do not narrow this back without reading it.
  Future<(DeviceController, FakeFlipperClient)> pumpApp(
    WidgetTester tester,
    Size size,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

  testWidgets('a poll tick rebuilds the nav bar and not the page stack', (
    tester,
  ) async {
    final (device, _) = await pumpApp(tester, const Size(500, 900));

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
    final (device, _) = await pumpApp(tester, const Size(500, 900));

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
    scaffoldIn(tester).onTabSelected(FlipperRootTab.archive);
    await tester.pumpAndSettle();

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
    final (device, _) = await pumpApp(tester, const Size(500, 900));

    scaffoldIn(tester).onTabSelected(FlipperRootTab.archive);
    await tester.pumpAndSettle();
    expect(visibleSlotIsDrawn(tester), isTrue, reason: 'blank while narrow');
    expect(selectedRailItems(tester), 1, reason: 'nothing lit while narrow');

    await tester.binding.setSurfaceSize(const Size(1200, 800));
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
}
