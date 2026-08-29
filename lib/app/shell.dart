import 'package:flutter/material.dart';

import 'nav_bar.dart';
import '../components/archive/category.dart';
import '../pages/apps/catalog/page.dart';
import '../pages/archive/browser/page.dart';
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
import '../theme/theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

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

  final DeviceController _ctrl = DeviceController();
  final ArchiveController _archiveController = ArchiveController();

  int _slot = _slotDevice;

  /// Slots built so far. Everything the mobile layout used to build eagerly
  /// stays eager; the rail-only pages mount on first visit.
  final Set<int> _mounted = <int>{_slotDevice, _slotArchive, _slotTools};

  @override
  void initState() {
    super.initState();
    _archiveController.addListener(_onArchiveChanged);
    _archiveController.initialize();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _archiveController.removeListener(_onArchiveChanged);
    _archiveController.dispose();
    _ctrl.client.disconnectAll();
    super.dispose();
  }

  void _onArchiveChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final wide = FlipperRootScaffold.isWide(context);
    final slot = _visibleSlot(wide);
    _mounted.add(slot);

    return DeviceScope(
      notifier: _ctrl,
      child: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) {
          return FlipperRootScaffold(
            currentTab: _tabOf(slot),
            onTabSelected: (tab) => _select(_slotOfTab(tab)),
            deviceLabel: _deviceLabel(),
            railGroups: _railGroups(colors, slot),
            child: IndexedStack(
              index: slot,
              children: [for (var i = 0; i < _slotCount; i++) _page(i, wide)],
            ),
          );
        },
      ),
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
    if (slot == _slotArchive) return ArchivePage(controller: _archiveController);
    if (slot == _slotFavorites) {
      return FavoritesPage(controller: _archiveController);
    }
    if (slot == _slotFiles) return const FileManagerPage(initialPath: '/ext');
    if (slot == _slotDeleted) return DeletedPage(controller: _archiveController);
    if (slot == _slotApps) return const AppsCatalogPage();
    if (slot == _slotTools) return const ToolsPage();
    return CategoryPage(
      controller: _archiveController,
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

  String _deviceLabel() {
    switch (_ctrl.connectionState) {
      case DeviceConnectionState.disconnected:
        return _ctrl.device != null ? 'Disconnected' : 'No device';
      case DeviceConnectionState.connecting:
        return 'Connecting';
      case DeviceConnectionState.dfu:
        return 'DFU';
      case DeviceConnectionState.recovering:
        return 'Recovering';
      case DeviceConnectionState.connected:
        if (_ctrl.deviceLoading) return 'Syncing';
        switch (_syncStatus) {
          case ArchiveSyncStatus.syncing:
            return 'Syncing';
          case ArchiveSyncStatus.synced:
            return _ctrl.deviceInfoConnected ? 'Connected' : 'Synced';
          case ArchiveSyncStatus.idle:
            return 'Connected';
        }
    }
  }

  ArchiveSyncStatus get _syncStatus => _archiveController.syncStatus;
}
