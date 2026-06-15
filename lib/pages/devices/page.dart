import 'package:flutter/material.dart';

import '../../widgets/root_scaffold.dart';
import '../apps/page.dart';
import '../archive/overview/controller.dart';
import '../archive/overview/page.dart';
import '../tools/overview/page.dart';
import 'controllers/device.dart';
import 'device_scope.dart';
import 'models/connection_state.dart';
import 'widgets/device_tab.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
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
    _ctrl.client.disconnect();
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
          return FlipperRootScaffold(
            currentTab: _tab,
            onTabSelected: _selectTab,
            deviceIconAsset: _deviceIconAsset(),
            deviceLabel: _deviceLabel(),
            child: IndexedStack(
              index: _tab.index,
              children: [
                const DeviceTab(),
                ArchivePage(controller: _archiveController),
                _appsMounted ? const AppsPage() : const SizedBox.shrink(),
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

  String _deviceIconAsset() {
    switch (_ctrl.connectionState) {
      case DeviceConnectionState.disconnected:
        return _ctrl.device != null
            ? 'assets/ic/connect/device-disconnected-filled.svg'
            : 'assets/ic/connect/device-missing-filled.svg';
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.recovering:
        return 'assets/ic/connect/device-syncing-filled.svg';
      case DeviceConnectionState.dfu:
        return 'assets/ic/connect/device-disconnected-filled.svg';
      case DeviceConnectionState.connected:
        if (_ctrl.deviceLoading) {
          return 'assets/ic/connect/device-syncing-filled.svg';
        }
        switch (_syncStatus) {
          case ArchiveSyncStatus.syncing:
            return 'assets/ic/connect/device-syncing-filled.svg';
          case ArchiveSyncStatus.synced:
            return _ctrl.deviceInfoConnected
                ? 'assets/ic/connect/device-connected-filled.svg'
                : 'assets/ic/connect/device-synced-filled.svg';
          case ArchiveSyncStatus.idle:
            return 'assets/ic/connect/device-connected-filled.svg';
        }
    }
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
