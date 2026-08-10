import 'package:flutter/material.dart';

import 'nav_bar.dart';
import '../pages/apps/catalog/page.dart';
import '../pages/archive/overview/controller.dart';
import '../pages/archive/overview/page.dart';
import '../pages/tools/overview/page.dart';
import '../pages/devices/controllers/device.dart';
import '../pages/devices/device_scope.dart';
import '../pages/devices/models/connection_state.dart';
import '../pages/devices/page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final DeviceController _ctrl = DeviceController();
  final ArchiveController _archiveController = ArchiveController();

  FlipperRootTab _tab = FlipperRootTab.device;
  bool _appsMounted = false;

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
    return DeviceScope(
      notifier: _ctrl,
      child: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) {
          final iconAsset = _deviceIconAsset();
          return FlipperRootScaffold(
            currentTab: _tab,
            onTabSelected: _selectTab,
            deviceIconAsset: iconAsset,
            deviceLabel: _deviceLabel(),
            deviceSyncing: iconAsset == _syncIcon,
            child: IndexedStack(
              index: _tab.index,
              children: [
                const DeviceTab(),
                ArchivePage(controller: _archiveController),
                _appsMounted
                    ? const AppsCatalogPage()
                    : const SizedBox.shrink(),
                const ToolsPage(),
              ],
            ),
          );
        },
      ),
    );
  }

  void _selectTab(FlipperRootTab tab) {
    setState(() {
      if (tab == FlipperRootTab.apps) _appsMounted = true;
      _tab = tab;
    });
  }

  static const _syncIcon = 'assets/ic/connect/sync.svg';

  String _deviceIconAsset() {
    switch (_ctrl.connectionState) {
      case DeviceConnectionState.disconnected:
        return _ctrl.device != null
            ? 'assets/ic/connect/disconnected.svg'
            : 'assets/ic/connect/missing.svg';
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.recovering:
        return _syncIcon;
      case DeviceConnectionState.dfu:
        return 'assets/ic/connect/disconnected.svg';
      case DeviceConnectionState.connected:
        if (_ctrl.deviceLoading) return _syncIcon;
        switch (_syncStatus) {
          case ArchiveSyncStatus.syncing:
            return _syncIcon;
          case ArchiveSyncStatus.synced:
            return _ctrl.deviceInfoConnected
                ? _transportIcon()
                : 'assets/ic/connect/synced.svg';
          case ArchiveSyncStatus.idle:
            return _transportIcon();
        }
    }
  }

  String _transportIcon() => _ctrl.device?.isBle == true
      ? 'assets/ic/connect/ble.svg'
      : 'assets/ic/connect/usb.svg';

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
