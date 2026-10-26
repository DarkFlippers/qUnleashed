import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';

import 'nav_bar.dart';
import '../components/archive/category.dart';
import '../components/open_url.dart';
import '../components/permission_notice.dart';
import '../pages/apps/catalog/page.dart';
import '../pages/archive/browser/page.dart';
import '../pages/archive/home_widget/picker_page.dart';
import '../pages/archive/overview/category/category_page.dart';
import '../pages/archive/overview/category/deleted_page.dart';
import '../pages/archive/overview/category/favorites_page.dart';
import '../pages/archive/overview/controller.dart';
import '../pages/archive/overview/page.dart';
import '../pages/tools/overview/page.dart';
import '../pages/devices/controllers/device.dart';
import '../pages/devices/device_scope.dart';
import '../pages/devices/models/connection_state.dart';
import '../pages/devices/page.dart';
import '../pages/option/diagnostics_notice.dart';
import '../pages/option/diagnostics_scope.dart';
import '../services/archive/sort_settings.dart';
import '../services/guarded.dart';
import '../services/home_widget/service.dart';
import '../services/localization/l10n.dart';
import '../services/notifications/push_intent.dart';
import '../services/notifications/push_service.dart';
import '../services/permissions/permission.dart';
import '../services/permissions/scope.dart';
import '../theme/theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.client});

  /// The Flipper the archive this shell owns talks to. Handed down rather
  /// than resolved here: `main.dart` calls itself the one place the client is
  /// resolved, and it only is if everything below takes one. ADR 0002.
  final FlipperClient client;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Slots of the shared page stack. The mobile bottom bar reaches device,
  // archive overview, apps and tools; the desktop rail reaches every slot but
  // the overview, whose content lives there as separate rail destinations.
  static const int _slotDevice = 0;
  static const int _slotArchive = 1;
  static const int _slotFavorites = 2;
  static const int _slotFiles = 3;
  static const int _slotCategory = 4;
  static final int _slotDeleted = _slotCategory + ArchiveCategory.values.length;
  static final int _slotApps = _slotDeleted + 1;
  static final int _slotTools = _slotApps + 1;
  static final int _slotCount = _slotTools + 1;

  late final ArchiveController _archiveController = ArchiveController(
    client: widget.client,
  );

  /// How the archive tables are ordered. Owned here rather than by a page
  /// because the rail keeps several of them mounted at once, and a sort the
  /// user changes on one has to reach the others. ADR 0002.
  final ArchiveSortSettings _archiveSort = ArchiveSortSettings();

  int _slot = _slotDevice;

  /// Slots built so far. Everything the mobile layout used to build eagerly
  /// stays eager; the rail-only pages mount on first visit.
  final Set<int> _mounted = <int>{_slotDevice, _slotArchive, _slotTools};

  @override
  void initState() {
    super.initState();
    // No listener on the archive controller here: its notification is taken
    // by the `ListenableBuilder` in `build`, which is the whole of #410 - see
    // the note there for what it used to cost.
    _archiveController.initialize();
    // Started as early as there is anywhere to start it, so the stored sort
    // is normally in hand before an archive table is reachable - but this is
    // a platform round trip and nothing waits for it. A table opened before
    // it lands shows name ascending and reorders once when it arrives, and
    // `ArchiveSortSettings` holds off the read for a user who picked first.
    //
    // `load` never rejects; `guarded` is for the dropped future, not the
    // error. #23.
    unawaited(
      guarded('[ArchiveSort] reading the stored sort', _archiveSort.load),
    );
    HomeWidgetService.instance.pickRequests.addListener(_onWidgetPickRequest);
    PushService.instance.taps.addListener(_onPushTap);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onWidgetPickRequest();
      _onPushTap();
      // ADR 0013 §1's one-time notice, raised here because here is the first
      // frame on the one entry point that has a window: `_initCore` must never
      // throw and has no UI, and `widgetMain()`'s headless isolate never
      // reaches this widget at all. A notice marked shown there would be a
      // notice the user never saw.
      //
      // `guarded` because a post-frame callback is a void slot: the future
      // would otherwise be dropped and a rejection would land as `[uncaught]`
      // naming nothing. #23.
      guarded(
        '[Diagnostics] raising the sharing notice',
        () => showDiagnosticsNoticeIfDue(context, DiagnosticsScope.of(context)),
      );
    });
  }

  @override
  void dispose() {
    HomeWidgetService.instance.pickRequests.removeListener(
      _onWidgetPickRequest,
    );
    PushService.instance.taps.removeListener(_onPushTap);
    _archiveController.dispose();
    _archiveSort.dispose();
    super.dispose();
  }

  void _onWidgetPickRequest() {
    final requests = HomeWidgetService.instance.pickRequests;
    final widgetId = requests.value;
    if (widgetId == null || !mounted) return;
    requests.value = null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomeWidgetPickerPage(
          widgetId: widgetId,
          controller: _archiveController,
        ),
      ),
    );
  }

  Future<void> _onPushTap() async {
    final intent = PushService.instance.taps.value;
    if (intent == null || !mounted) return;
    if (intent.type == PushIntent.typeFirmware) {
      _select(_slotDevice);
      return;
    }
    PushService.instance.taps.value = null;
    final url = intent.url;
    if (intent.type != PushIntent.typeApp || url == null) return;
    await openUrl(context, url);
  }

  /// Whether a Bluetooth denial leaves this app with nothing to do.
  ///
  /// Two conditions, and both matter. The platform one is iOS alone -
  /// Android keeps USB-OTG, which makes the same denial a feature gate the
  /// device picker draws instead. The outcome one is `denied` exactly: an
  /// unknown or unavailable answer must never raise this screen, because
  /// blocking the whole app on a guess is worse than the silence it
  /// replaces.
  bool _bluetoothBlocks(BuildContext context) {
    final center = PermissionScope.maybeOf(context);
    if (center == null) return false;
    // Asked through `tierOf` rather than re-derived from `Platform.isIOS`
    // here. `AppPermission.tier` was made a pure function precisely so this
    // decision could be tested on both platforms, and open-coding it meant
    // the one branch that blacks out the whole app had no test at all.
    if (center.tierOf(AppPermission.bluetooth) != PermissionTier.blocking) {
      return false;
    }
    // `denied` exactly. An unknown or unavailable answer must never raise
    // this screen: blocking the app on a guess is worse than the silence it
    // replaces.
    return center.outcomeOf(AppPermission.bluetooth).warrantsNotice;
  }

  Widget _blockingGate(BuildContext context) {
    return PermissionGate(
      icon: Icons.bluetooth_disabled,
      title: context.l10n.permissionBluetoothBlockedTitle,
      body: context.l10n.permissionBluetoothBlockedBody,
      hint: context.l10n.permissionBluetoothBlockedHint,
      actionLabel: context.l10n.permissionOpenSettings,
      // No re-check button beside it. `PermissionCenter` re-reads on
      // resume, so coming back from settings clears this by itself -
      // which is what the footnote on the screen promises.
      onAction: _openAppSettings,
    );
  }

  void _openAppSettings() =>
      unawaited(openPermissionSettings(context, '[Gate] opening app settings'));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final wide = FlipperRootScaffold.isWide(context);
    final slot = _visibleSlot(wide);
    _mounted.add(slot);

    // Provided above the Navigator now, so this reads it like every other
    // page rather than owning it - ADR 0011.
    //
    // `notifierOf`, so the poll does not rebuild *this*. The read used to be
    // listening, which subscribed this element - so every tick re-ran the
    // lines above as well as the builder below, and the `ListenableBuilder`
    // narrowed nothing at all.
    //
    // The controller's state *is* read, by `_deviceLabel`, but only from
    // inside the builder - whose element holds the subscription, so the label
    // follows the device. Nothing below reads a *value* off it; the merge at
    // the foot of this method only subscribes to it. That is what makes a
    // non-listening read correct here. #407.
    final device = DeviceScope.notifierOf(context);

    // Tier 1. The only permission that reaches it is Bluetooth on iOS,
    // where `transport/usb/ios.dart` throws `UnsupportedError` and there is
    // no second transport - so every tab behind this is furniture and a
    // notice inside one of them would be a notice on a dead screen. #351.
    //
    // Replaces the shell rather than covering it: there is nothing usable
    // underneath, and a dismissible sheet over an empty app is how the user
    // ends up staring at the empty app.
    if (_bluetoothBlocks(context)) return _blockingGate(context);

    // **The page stack is built out here and handed through, not rebuilt
    // inside the builder.** `ListenableBuilder.child` exists for exactly this:
    // it passes the same widget instance back, and `Element.updateChild`
    // skips a child whose widget is identical - so a notification rebuilds
    // this scaffold and its nav bar, and **every mounted page's `build` is
    // skipped**.
    //
    // That is the saving, and it is worth being exact about: built inside the
    // closure it was a new `IndexedStack` every tick, which *updates* its
    // children rather than tearing them down, so `State` objects and scroll
    // positions survived either way. What they paid was a `build` per mounted
    // page, twelve times a minute.
    //
    // The only thing in here that depends on either controller is
    // `deviceLabel` - one string, drawn in the bottom bar - and the wide
    // layout does not draw even that: `FlipperRootScaffold` ignores
    // `deviceLabel`, `currentTab` and `onTabSelected` entirely when `isWide`,
    // so on desktop a tick was rebuilding the whole app for a value nothing
    // displayed. #407, #410.
    final pages = IndexedStack(
      index: slot,
      children: [for (var i = 0; i < _slotCount; i++) _page(i, wide)],
    );

    // Out here with it: neither depends on either controller, and
    // `_railGroups` builds a fresh list of lists, with a `FlipperRailIcon` per
    // item, every time it is called. Inside the builder they were recomputed
    // on every tick along with the label.
    final railGroups = _railGroups(colors, slot);
    final currentTab = _tabOf(slot);

    // **Only the sync status, not the archive controller.** `_deviceLabel`
    // reads `syncStatus` for the `connected` case and nothing else off that
    // controller, and `ArchiveController` exposes it as a `ValueNotifier` -
    // which notifies on `!=` - so the bottom bar follows a sync without being
    // woken by the forty-one places the controller notifies from. ADR 0011's
    // #410 addendum has the rates, and why this is merged in `build` rather
    // than held in a field.
    //
    // #410 supposed the shell read no *value* off the archive controller at
    // all, in which case its listener could simply have gone. Dropping it
    // would have stopped the bar following a sync - lagging to the next
    // five-second device tick rather than freezing, because the device
    // controller is in this same merge.
    final repaint = Listenable.merge([device, _archiveController.syncStatus]);

    return ListenableBuilder(
      listenable: repaint,
      child: pages,
      builder: (context, child) {
        return FlipperRootScaffold(
          currentTab: currentTab,
          onTabSelected: (tab) => _select(_slotOfTab(tab)),
          deviceLabel: _deviceLabel(device),
          railGroups: railGroups,
          child: child!,
        );
      },
    );
  }

  /// Slot actually shown for the current layout. The overview screen is mobile
  /// only, and the rail-only archive pages have no mobile tab of their own, so
  /// each layout falls back to its own archive entry point while [_slot] keeps
  /// the other layout's choice for when the window flips back.
  int _visibleSlot(bool wide) {
    if (wide) return _slot == _slotArchive ? _slotFavorites : _slot;
    return _isArchiveDetail(_slot) ? _slotArchive : _slot;
  }

  bool _isArchiveDetail(int slot) =>
      slot >= _slotFavorites && slot <= _slotDeleted;

  void _select(int slot) {
    setState(() {
      _mounted.add(slot);
      _slot = slot;
    });
  }

  FlipperRootTab _tabOf(int slot) {
    if (slot == _slotDevice) return FlipperRootTab.device;
    if (slot == _slotApps) return FlipperRootTab.apps;
    if (slot == _slotTools) return FlipperRootTab.tools;
    return FlipperRootTab.archive;
  }

  int _slotOfTab(FlipperRootTab tab) {
    switch (tab) {
      case FlipperRootTab.device:
        return _slotDevice;
      case FlipperRootTab.archive:
        return _slotArchive;
      case FlipperRootTab.apps:
        return _slotApps;
      case FlipperRootTab.tools:
        return _slotTools;
    }
  }

  /// Builds one slot. A page belonging to the other layout is left out of the
  /// stack entirely: the overview screen is mobile only, the rail pages desktop
  /// only, and an off-layout page would still register its [PopScope] on the
  /// route and swallow the system back gesture.
  Widget _page(int slot, bool wide) {
    if (!_mounted.contains(slot)) return const SizedBox.shrink();
    if (wide && slot == _slotArchive) return const SizedBox.shrink();
    if (!wide && _isArchiveDetail(slot)) return const SizedBox.shrink();
    if (slot == _slotDevice) return const DeviceTab();
    if (slot == _slotArchive) {
      return ArchivePage(
        controller: _archiveController,
        sortSettings: _archiveSort,
      );
    }
    if (slot == _slotFavorites) {
      return FavoritesPage(
        controller: _archiveController,
        sortSettings: _archiveSort,
      );
    }
    if (slot == _slotFiles) {
      return FileManagerPage(client: widget.client, initialPath: '/ext');
    }
    if (slot == _slotDeleted) {
      return DeletedPage(
        controller: _archiveController,
        sortSettings: _archiveSort,
      );
    }
    if (slot == _slotApps) return const AppsCatalogPage();
    if (slot == _slotTools) return const ToolsPage();
    return CategoryPage(
      controller: _archiveController,
      sortSettings: _archiveSort,
      category: ArchiveCategory.values[slot - _slotCategory],
    );
  }

  List<List<FlipperRailItem>> _railGroups(QAppColors colors, int slot) {
    return [
      [
        _railItem(
          colors,
          slot,
          _slotDevice,
          colors.accent,
          asset: 'assets/ic/device/flipper.svg',
        ),
      ],
      [
        _railItem(
          colors,
          slot,
          _slotFiles,
          const Color(0xFF8BC34A),
          asset: 'assets/ic/app/files.svg',
        ),
        for (final cat in ArchiveCategory.values)
          _railItem(
            colors,
            slot,
            _slotCategory + cat.index,
            cat.color,
            asset: cat.asset,
          ),
        _railItem(
          colors,
          slot,
          _slotDeleted,
          const Color(0xFF8D8D8D),
          asset: 'assets/ic/fileformat/deleted.svg',
        ),
        _railItem(
          colors,
          slot,
          _slotFavorites,
          const Color(0xFFFFC107),
          asset: 'assets/ic/fileformat/favorites.svg',
        ),
      ],
      [
        _railItem(
          colors,
          slot,
          _slotApps,
          colors.accent,
          asset: 'assets/ic/app/apps.svg',
        ),
        _railItem(
          colors,
          slot,
          _slotTools,
          colors.accent,
          asset: 'assets/ic/appcat/tools.svg',
        ),
      ],
    ];
  }

  FlipperRailItem _railItem(
    QAppColors colors,
    int slot,
    int target,
    Color color, {
    required String asset,
  }) {
    final selected = slot == target;
    final tint = selected ? color : colors.textMuted;
    return FlipperRailItem(
      icon: FlipperRailIcon(asset: asset, color: tint),
      color: color,
      selected: selected,
      onTap: () => _select(target),
    );
  }

  String _deviceLabel(DeviceController device) {
    final strings = l10n;
    switch (device.connectionState) {
      case DeviceConnectionState.disconnected:
        return device.device != null
            ? strings.deviceStateDisconnected
            : strings.deviceStateNoDevice;
      case DeviceConnectionState.connecting:
        return strings.deviceStateConnecting;
      case DeviceConnectionState.dfu:
        return strings.deviceStateDfu;
      case DeviceConnectionState.recovering:
        return strings.deviceStateRecovering;
      case DeviceConnectionState.connected:
        if (device.deviceLoading) return strings.deviceStateSyncing;
        // **Three statuses, three strings**, and `synced` draws the one
        // the ARB describes as "when the archive finished syncing": what
        // `ArchiveController.syncAll` means by reaching it, and what
        // `syncCategory` deliberately does not claim.
        //
        // The arm used to be guarded on `DeviceController`'s
        // `deviceInfoConnected`, which says nothing about the archive and is
        // implied by `connected && !deviceLoading` besides - every route to
        // `isConnected` runs `_ensureDataLoading`, which leaves one of that
        // pair set - so the string and its seven translations were
        // unreachable. The flag was the wrong thing to read, not the branch
        // the wrong thing to have; a connectedness guard here is the mistake
        // not to re-add. #420.
        switch (_syncStatus) {
          case ArchiveSyncStatus.syncing:
            return strings.deviceStateSyncing;
          case ArchiveSyncStatus.synced:
            return strings.deviceStateSynced;
          case ArchiveSyncStatus.idle:
            return strings.deviceStateConnected;
        }
    }
  }

  ArchiveSyncStatus get _syncStatus => _archiveController.syncStatus.value;
}
