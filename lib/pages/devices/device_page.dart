import 'dart:async';

import 'package:flipperlib/discovered_device.dart';
import 'package:flipperlib/log_service.dart';
import 'package:flipperlib/protobuf.dart';
import 'package:flutter/material.dart';

import '../../services/flipper_protocol.dart';
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
  FlipperRootTab _tab = FlipperRootTab.device;

  ConnectedDevice? _device;
  bool _deviceDisconnected = false;

  Map<String, String> _info = {};
  final List<String> _logs = [];
  FlipperFrameBuffer _buffer = FlipperFrameBuffer();
  final Set<int> _pending = {};
  String _deviceStatus = '';
  bool _deviceLoading = false;

  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<String>? _logSub;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _cleanupDevice(disconnect: true);
    super.dispose();
  }

  void _cleanupDevice({required bool disconnect}) {
    _timeoutTimer?.cancel();
    _logSub?.cancel();
    _dataSub?.cancel();
    if (disconnect && !_deviceDisconnected) {
      _device?.disconnect();
    }
  }

  Future<void> _openPicker() async {
    final selected = await showConnectionDialog(context);
    if (selected != null && mounted) {
      _connectTo(selected);
    }
  }

  Future<void> _connectTo(DiscoveredDevice device) async {
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
      final connected = await device.connect();
      if (!mounted) return;
      Navigator.of(context).pop();
      _setupDevice(connected);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      LogService.log('[DevicePage] connection failed: $e');
    }
  }

  void _setupDevice(ConnectedDevice connected) {
    _cleanupDevice(disconnect: false);
    setState(() {
      _device = connected;
      _deviceDisconnected = false;
      _info = {};
      _buffer = FlipperFrameBuffer();
      _pending.clear();
      _deviceStatus = 'Initializing...';
      _deviceLoading = true;
    });

    _logSub = LogService.stream.listen((line) {
      if (!mounted) return;
      setState(() => _logs.add(line));
    });

    _dataSub = connected.dataStream.listen(
      _onData,
      onError: (e) {
        LogService.log('[DevicePage] stream error: $e');
        if (!mounted) return;
        setState(() {
          _deviceStatus = 'Connection failed';
          _deviceLoading = false;
        });
      },
      onDone: () {
        LogService.log('[DevicePage] stream closed');
        if (!mounted) return;
        setState(() {
          _deviceStatus = 'Disconnected';
          _deviceDisconnected = true;
          _deviceLoading = false;
        });
      },
    );

    _initDevice(connected);
  }

  Future<void> _initDevice(ConnectedDevice connected) async {
    try {
      await connected.init();
    } catch (e) {
      LogService.log('[DevicePage] init error: $e');
      if (!mounted) return;
      setState(() {
        _deviceStatus = 'Initialization failed';
        _deviceLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _deviceStatus = 'Requesting device info...');
    }
    await _requestAll(connected);
  }

  Future<void> _requestAll(ConnectedDevice connected) async {
    try {
      final protoId = FlipperProtocol.nextCommandId();
      _pending.add(protoId);
      await connected.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: protoId, systemProtobufVersionRequest: ProtobufVersionRequest()),
        ),
      );

      final deviceId = FlipperProtocol.nextCommandId();
      _pending.add(deviceId);
      await connected.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: deviceId, systemDeviceInfoRequest: DeviceInfoRequest()),
        ),
      );

      final powerId = FlipperProtocol.nextCommandId();
      _pending.add(powerId);
      await connected.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: powerId, systemPowerInfoRequest: PowerInfoRequest()),
        ),
      );

      final datetimeId = FlipperProtocol.nextCommandId();
      _pending.add(datetimeId);
      await connected.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: datetimeId, systemGetDatetimeRequest: GetDateTimeRequest()),
        ),
      );

      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted || !_deviceLoading) return;
        setState(() {
          _deviceStatus = _info.isEmpty ? 'Timeout — no response' : 'Timeout — partial data';
          _deviceLoading = false;
        });
      });
    } catch (e) {
      LogService.log('[DevicePage] send error: $e');
      if (!mounted) return;
      setState(() {
        _deviceStatus = 'Request failed';
        _deviceLoading = false;
      });
    }
  }

  void _onData(List<int> raw) {
    final messages = _buffer.push(raw);
    for (final msg in messages) {
      if (mounted) {
        setState(() => _handleMessage(msg));
      }
    }
  }

  void _handleMessage(Main msg) {
    if (msg.commandStatus == CommandStatus.ERROR_DECODE) {
      if (msg.commandId == 0 && _pending.isNotEmpty) {
        _pending.clear();
        _checkDone();
      }
      return;
    }

    switch (msg.whichContent()) {
      case Main_Content.systemProtobufVersionResponse:
        final response = msg.systemProtobufVersionResponse;
        _info['protobuf_version'] = '${response.major}.${response.minor}';
        _markDone(msg.commandId);
        break;
      case Main_Content.systemDeviceInfoResponse:
        final response = msg.systemDeviceInfoResponse;
        _info[response.key] = response.value;
        if (!msg.hasNext) _markDone(msg.commandId);
        break;
      case Main_Content.systemPowerInfoResponse:
        final response = msg.systemPowerInfoResponse;
        _info['power.${response.key}'] = response.value;
        if (!msg.hasNext) _markDone(msg.commandId);
        break;
      case Main_Content.systemGetDatetimeResponse:
        final dt = msg.systemGetDatetimeResponse.datetime;
        _info['datetime'] =
            '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
        _markDone(msg.commandId);
        break;
      default:
        break;
    }
  }

  void _markDone(int id) {
    _pending.remove(id);
    _checkDone();
  }

  void _checkDone() {
    if (_pending.isEmpty && _deviceLoading) {
      _timeoutTimer?.cancel();
      _deviceStatus = 'Connected';
      _deviceLoading = false;
      QAppThemeController.instance.syncFirmwareFromDeviceInfo(_info);
    }
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

  String get _deviceName =>
      _firstInfo(['hardware_name', 'device_name', 'name'], fallback: _device?.name ?? 'Flipper Zero');

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
    _timeoutTimer?.cancel();
    _deviceDisconnected = true;
    await _device?.disconnect();
    if (!mounted) return;
    setState(() {
      _device = null;
      _deviceDisconnected = false;
    });
  }

  Future<void> _openRemoteControl() async {
    final device = _device;
    if (device == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RemoteControlPage(device: device)),
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

  void _synchronizeDevice(ConnectedDevice device) {
    setState(() {
      _deviceLoading = true;
      _deviceStatus = 'Refreshing...';
      _pending.clear();
      _info.clear();
    });
    _requestAll(device);
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
                  onSynchronize: _deviceLoading ? null : () => _synchronizeDevice(device),
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
