import 'package:flutter/material.dart';

import '../../widgets/root_scaffold.dart';
import '../apps/page.dart';
import '../archive/controller.dart';
import '../archive/page.dart';
import '../tools/page.dart';
import 'controller.dart';
import 'scope.dart';
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
            onTabSelected: (tab) => setState(() => _tab = tab),
            deviceIconAsset: _deviceIconAsset(),
            deviceLabel: _deviceLabel(),
            child: IndexedStack(
              index: _tab.index,
              children: [
                const DeviceTab(),
                ArchivePage(controller: _archiveController),
                const AppsPage(),
                const ToolsPage(),
              ],
            ),
          );
        },
      ),
    );
  }

  String _deviceIconAsset() {
    final isConnected = _ctrl.isConnected;
    if (!isConnected) {
      return _ctrl.device != null
          ? 'assets/flipper_svg/connection/ic_disconnected_filled.svg'
          : 'assets/flipper_svg/connection/ic_no_device_filled.svg';
    }
    if (_ctrl.deviceLoading) {
      return 'assets/flipper_svg/connection/ic_syncing_filled.svg';
    }
    switch (_syncStatus) {
      case ArchiveSyncStatus.syncing:
        return 'assets/flipper_svg/connection/ic_syncing_filled.svg';
      case ArchiveSyncStatus.synced:
        return _ctrl.deviceInfoConnected
            ? 'assets/flipper_svg/connection/ic_connected_filled.svg'
            : 'assets/flipper_svg/connection/ic_synced_filled.svg';
      case ArchiveSyncStatus.idle:
        return 'assets/flipper_svg/connection/ic_connected_filled.svg';
    }
  }

  String _deviceLabel() {
    if (!_ctrl.isConnected) {
      return _ctrl.device != null ? 'Disconnected' : 'No device';
    }
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

  ArchiveSyncStatus get _syncStatus => _archiveController.syncStatus;
}
