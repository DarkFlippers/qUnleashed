import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/device_full_info_sheet.dart';
import '../../widgets/device_logs_sheet.dart';
import '../../widgets/device_shell.dart';
import '../apps/apps_page.dart';
import '../archive/archive_page.dart';
import '../tools/tools_page.dart';
import '../widgets/connection.dart';
import 'remote_control_page.dart';
import 'widgets/connected_device_view.dart';
import 'widgets/disconnected_device_view.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final FlipperClient _client = FlipperOneClient().get();

  FlipperRootTab _tab = FlipperRootTab.device;
  FlipperDevice? _device;
  bool _deviceDisconnected = false;
  bool _deviceLoading = false;
  Map<String, String> _info = {};
  final List<String> _logs = [];

  StreamSubscription<FlipperConnectionState>? _connectionSub;
  StreamSubscription<String>? _logSub;

  @override
  void initState() {
    super.initState();
    _device = _client.connectedDevice;
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    _logSub = LogService.stream.listen((line) {
      if (!mounted) return;
      setState(() => _logs.add(line));
    });
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _logSub?.cancel();
    _client.disconnect();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final selected = await showConnectionDialog(context);
    if (selected != null && mounted) {
      _connectTo(selected);
    }
  }

  Future<void> _connectTo(FlipperDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Connecting...'),
          ],
        ),
      ),
    );

    try {
      final connected = await _client.connect(device);
      if (!mounted) return;
      Navigator.of(context).pop();
      _setupDevice(connected);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      LogService.log('[DevicePage] connection failed: $e');
    }
  }

  void _setupDevice(FlipperDevice device) {
    setState(() {
      _device = device;
      _deviceDisconnected = false;
      _deviceLoading = true;
      _info = {};
    });
    _requestAll();
  }

  Future<void> _requestAll() async {
    try {
      final results = await Future.wait([
        _client.protobufVersion(timeout: const Duration(seconds: 15)),
        _client.deviceInfo(timeout: const Duration(seconds: 15)),
        _client.powerInfo(timeout: const Duration(seconds: 15)),
        _client.getDateTime(timeout: const Duration(seconds: 15)),
      ]);

      final protobuf = results[0] as FlipperRpcBatch<ProtobufVersionResponse>;
      final deviceInfo = results[1] as FlipperRpcBatch<DeviceInfoResponse>;
      final powerInfo = results[2] as FlipperRpcBatch<PowerInfoResponse>;
      final dateTime = results[3] as FlipperRpcBatch<GetDateTimeResponse>;

      final info = <String, String>{
        'protobuf_version': '${protobuf.single.major}.${protobuf.single.minor}',
      };

      for (final item in deviceInfo.items) {
        info[item.key] = item.value;
      }
      for (final item in powerInfo.items) {
        info['power.${item.key}'] = item.value;
      }

      final dt = dateTime.single.datetime;
      info['datetime'] =
          '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';

      if (!mounted) return;
      setState(() {
        _info = info;
        _deviceLoading = false;
      });
      QAppThemeController.instance.syncFirmwareFromDeviceInfo(info);
    } catch (e) {
      LogService.log('[DevicePage] request failed: $e');
      if (!mounted) return;
      setState(() {
        _deviceLoading = false;
      });
    }
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    if (state.connected) {
      setState(() {
        _device = state.device;
        _deviceDisconnected = false;
      });
      return;
    }
    setState(() {
      _deviceDisconnected = true;
      _deviceLoading = false;
    });
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String get _deviceFirmwareVersion =>
      _info['firmware_version'] ??
      _info['firmware.version'] ??
      _info['software_revision'] ??
      _info['protobuf_version'] ??
      '-';

  String get _buildDate =>
      _info['firmware_build_date'] ?? _info['build_date'] ?? _info['datetime'] ?? '-';

  String get _sdCard =>
      _info['storage.sdcard.used'] != null || _info['storage.sdcard.total'] != null
          ? '${_info['storage.sdcard.used'] ?? '?'} / ${_info['storage.sdcard.total'] ?? '?'}'
          : '-';

  String get _internalFlash =>
      _info['storage.internal.used'] != null || _info['storage.internal.total'] != null
          ? '${_info['storage.internal.used'] ?? '?'} / ${_info['storage.internal.total'] ?? '?'}'
          : '-';

  String get _deviceName => _firstInfo(
        ['hardware_name', 'device_name', 'name'],
        fallback: _device?.name ?? 'Flipper Zero',
      );

  String _firstInfo(List<String> keys, {String fallback = '-'}) {
    for (final key in keys) {
      final value = _info[key];
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _device = null;
      _deviceDisconnected = false;
      _deviceLoading = false;
      _info = {};
    });
  }

  Future<void> _openRemoteControl() async {
    if (_device == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
  }

  void _openFullInfo() {
    showDeviceFullInfoSheet(
      context,
      title: 'Full Info',
      cards: [
        FlipperPageCard(
          title: 'Firmware',
          child: Column(
            children: [
              FlipperInfoLine(label: 'Firmware Version', value: _deviceFirmwareVersion),
              Divider(height: 1, color: context.appColors.divider),
              FlipperInfoLine(label: 'Build Date', value: _buildDate),
              Divider(height: 1, color: context.appColors.divider),
              FlipperInfoLine(label: 'SD Card (Used/Total)', value: _sdCard),
              Divider(height: 1, color: context.appColors.divider),
              FlipperInfoLine(label: 'Int. Flash (Used/Total)', value: _internalFlash),
            ],
          ),
        ),
        RawInfoCard(entries: _info),
      ],
    );
  }

  void _openLogs() {
    showDeviceLogsSheet(
      context,
      logs: _logs,
      onClear: () => setState(_logs.clear),
    );
  }

  void _synchronizeDevice() {
    setState(() {
      _deviceLoading = true;
      _info = {};
    });
    _requestAll();
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final isConnected = device != null && !_deviceDisconnected;

    return FlipperRootScaffold(
      currentTab: _tab,
      onTabSelected: (tab) => setState(() => _tab = tab),
      deviceIconAsset: isConnected
          ? 'assets/flipper_svg/connection/ic_connected_filled.svg'
          : 'assets/flipper_svg/connection/ic_no_device_filled.svg',
      deviceLabel: isConnected ? 'Connected' : 'No device',
      child: IndexedStack(
        index: _tab.index,
        children: [
          isConnected
              ? ConnectedDeviceView(
                  deviceName: _deviceName,
                  infoLoading: _deviceLoading,
                  deviceFirmwareVersion: _deviceFirmwareVersion,
                  buildDate: _buildDate,
                  internalFlash: _internalFlash,
                  sdCard: _sdCard,
                  onSynchronize: _deviceLoading ? null : _synchronizeDevice,
                  onOpenRemoteControl: _openRemoteControl,
                  onOpenFullInfo: _openFullInfo,
                  onDisconnect: _disconnect,
                )
              : DisconnectedDeviceView(onConnect: _openPicker),
          const ArchivePage(),
          const AppsPage(),
          ToolsPage(
            connected: isConnected,
            onOpenLogs: _openLogs,
          ),
        ],
      ),
    );
  }
}
