import 'dart:async';

import 'package:flipperzero/flipperzero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/discovered_device.dart';
import '../services/flipper_protocol.dart';
import '../services/log_service.dart';
import '../widgets/device_shell.dart';
import 'remote_control.dart';

class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key, required this.device});

  final ConnectedDevice device;

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  final Map<String, String> _info = {};
  final List<String> _logs = [];
  final _buf = FlipperFrameBuffer();
  final Set<int> _pending = {};

  String _status = 'Initializing...';
  bool _loading = true;
  bool _disconnected = false;
  FlipperRootTab _tab = FlipperRootTab.device;

  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<String>? _logSub;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    _logSub = LogService.stream.listen((line) {
      if (!mounted) return;
      setState(() => _logs.add(line));
    });

    _dataSub = widget.device.dataStream.listen(
      _onData,
      onError: (e) {
        LogService.log('[DeviceInfo] stream error: $e');
        if (!mounted) return;
        setState(() {
          _status = 'Connection failed';
          _loading = false;
        });
      },
      onDone: () {
        LogService.log('[DeviceInfo] stream closed');
        if (!mounted) return;
        setState(() {
          _status = 'Disconnected';
          _disconnected = true;
          _loading = false;
        });
      },
    );

    _initAndRequest();
  }

  Future<void> _initAndRequest() async {
    try {
      await widget.device.init();
    } catch (e) {
      LogService.log('[DeviceInfo] init error: $e');
      if (!mounted) return;
      setState(() {
        _status = 'Initialization failed';
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _status = 'Requesting device info...');
    await _requestAll();
  }

  Future<void> _requestAll() async {
    try {
      final protoId = FlipperProtocol.nextCommandId();
      _pending.add(protoId);
      await widget.device.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: protoId, systemProtobufVersionRequest: ProtobufVersionRequest()),
        ),
      );

      final devId = FlipperProtocol.nextCommandId();
      _pending.add(devId);
      await widget.device.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: devId, systemDeviceInfoRequest: DeviceInfoRequest()),
        ),
      );

      final pwrId = FlipperProtocol.nextCommandId();
      _pending.add(pwrId);
      await widget.device.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: pwrId, systemPowerInfoRequest: PowerInfoRequest()),
        ),
      );

      final dtId = FlipperProtocol.nextCommandId();
      _pending.add(dtId);
      await widget.device.sendBytes(
        FlipperProtocol.encode(
          Main(commandId: dtId, systemGetDatetimeRequest: GetDateTimeRequest()),
        ),
      );

      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted || !_loading) return;
        setState(() {
          _status = _info.isEmpty
              ? 'Timeout - no response from device'
              : 'Timeout - partial data for ${widget.device.name}';
          _loading = false;
        });
      });
    } catch (e) {
      LogService.log('[DeviceInfo] send error: $e');
      if (!mounted) return;
      setState(() {
        _status = 'Request failed';
        _loading = false;
      });
    }
  }

  void _onData(List<int> raw) {
    final messages = _buf.push(raw);
    for (final msg in messages) {
      if (mounted) setState(() => _handleMessage(msg));
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
        final r = msg.systemProtobufVersionResponse;
        _info['protobuf_version'] = '${r.major}.${r.minor}';
        _markDone(msg.commandId);
        break;
      case Main_Content.systemDeviceInfoResponse:
        final r = msg.systemDeviceInfoResponse;
        _info[r.key] = r.value;
        if (!msg.hasNext) _markDone(msg.commandId);
        break;
      case Main_Content.systemPowerInfoResponse:
        final r = msg.systemPowerInfoResponse;
        _info['power.${r.key}'] = r.value;
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

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _markDone(int commandId) {
    _pending.remove(commandId);
    _checkDone();
  }

  void _checkDone() {
    if (_pending.isEmpty && _loading) {
      _timeoutTimer?.cancel();
      _status = 'Connected';
      _loading = false;
    }
  }

  String get _deviceInfoVersion =>
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

  String get _deviceName => _firstInfoValue([
        'hardware_name',
        'device_name',
        'name',
      ], fallback: widget.device.name);

  String get _hardwareModel => _firstInfoValue([
        'hardware_model',
        'model',
      ]);

  String get _hardwareRegion => _firstInfoValue([
        'hardware_region',
        'region',
      ]);

  String get _hardwareVersion => _firstInfoValue([
        'hardware_ver',
        'hardware_version',
      ]);

  String get _serialNumber => _firstInfoValue([
        'hardware_uid',
        'serial_number',
        'serial',
      ]);

  String get _softwareRevision => _firstInfoValue([
        'software_revision',
        'firmware_commit',
      ]);

  String get _target => _firstInfoValue([
        'firmware_target',
        'target',
      ]);

  String get _radioFirmware => _firstInfoValue([
        'radio_stack',
        'radio_firmware',
      ]);

  String get _battery => _firstInfoValue([
        'power.battery.level',
        'power.charge_level',
        'power.battery.current',
      ]);

  String _firstInfoValue(List<String> keys, {String fallback = '-'}) {
    for (final key in keys) {
      final value = _info[key];
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _logSub?.cancel();
    _dataSub?.cancel();
    if (!_disconnected) widget.device.disconnect();
    super.dispose();
  }

  Future<void> _disconnect() async {
    _timeoutTimer?.cancel();
    _disconnected = true;
    await widget.device.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openRemoteControl() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RemoteControlScreen(device: widget.device),
      ),
    );
  }

  void _openFullInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.6,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: FlipperOriginalColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FlipperOriginalColors.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'Full Info',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: FlipperOriginalColors.text100,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Flipper Device',
                child: Column(
                  children: [
                    FlipperInfoLine(label: 'Device Name', value: _deviceName),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Hardware Model', value: _hardwareModel),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Hardware Region', value: _hardwareRegion),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Hardware Version', value: _hardwareVersion),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Serial Number', value: _serialNumber),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Firmware',
                child: Column(
                  children: [
                    FlipperInfoLine(label: 'Firmware Version', value: _deviceInfoVersion),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Software Revision', value: _softwareRevision),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Build Date', value: _buildDate),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Target', value: _target),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Protobuf Version', value: _firstInfoValue(['protobuf_version'])),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Other',
                child: Column(
                  children: [
                    FlipperInfoLine(label: 'Radio Firmware', value: _radioFirmware),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Int. Flash (Used/Total)', value: _internalFlash),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'SD Card (Used/Total)', value: _sdCard),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Battery', value: _battery),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Device Time', value: _firstInfoValue(['datetime'])),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Raw Data',
                child: _info.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'No data received.',
                          style: TextStyle(
                            fontSize: 14,
                            color: FlipperOriginalColors.text30,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (final entry in (_info.entries.toList()
                                ..sort((a, b) => a.key.compareTo(b.key))))
                            Column(
                              children: [
                                FlipperInfoLine(label: entry.key, value: entry.value),
                                if (entry.key != (_info.entries.toList()
                                      ..sort((a, b) => a.key.compareTo(b.key)))
                                    .last
                                    .key)
                                  const Divider(height: 1, color: FlipperOriginalColors.divider),
                              ],
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _openTerminal() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF090909),
        child: SizedBox(
          width: 900,
          height: 560,
          child: Column(
            children: [
              Container(
                color: const Color(0xFF151515),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Text(
                      'Terminal',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(_logs.clear),
                      child: const Text('Clear'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _logs.isEmpty
                    ? const Center(
                        child: Text('No logs yet.', style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Text(
                          _logs[i],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.4,
                            color: Color(0xFF90EE90),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlipperRootScaffold(
      currentTab: _tab,
      onTabSelected: (tab) => setState(() => _tab = tab),
      deviceIconAsset: _disconnected
          ? 'assets/flipper_svg/connection/ic_disconnected_filled.svg'
          : 'assets/flipper_svg/connection/ic_connected_filled.svg',
      deviceLabel: _disconnected ? 'Not connected' : 'Connected',
      child: IndexedStack(
        index: _tab.index,
        children: [
          _ConnectedDevicePage(
            deviceName: _deviceName,
            status: _status,
            loading: _loading,
            version: _deviceInfoVersion,
            buildDate: _buildDate,
            internalFlash: _internalFlash,
            sdCard: _sdCard,
            onSynchronize: _loading
                ? null
                : () {
                    setState(() {
                      _loading = true;
                      _status = 'Refreshing...';
                      _pending.clear();
                      _info.clear();
                    });
                    _requestAll();
                  },
            onOpenRemoteControl: _openRemoteControl,
            onOpenFullInfo: _openFullInfo,
            onOpenTerminal: _openTerminal,
            onDisconnect: _disconnect,
          ),
          const Center(child: Text('Archive')),
          const Center(child: Text('Apps')),
          const Center(child: Text('Tools')),
        ],
      ),
    );
  }
}

class _ConnectedDevicePage extends StatelessWidget {
  const _ConnectedDevicePage({
    required this.deviceName,
    required this.status,
    required this.loading,
    required this.version,
    required this.buildDate,
    required this.internalFlash,
    required this.sdCard,
    required this.onSynchronize,
    required this.onOpenRemoteControl,
    required this.onOpenFullInfo,
    required this.onOpenTerminal,
    required this.onDisconnect,
  });

  final String deviceName;
  final String status;
  final bool loading;
  final String version;
  final String buildDate;
  final String internalFlash;
  final String sdCard;
  final VoidCallback? onSynchronize;
  final VoidCallback onOpenRemoteControl;
  final VoidCallback onOpenFullInfo;
  final VoidCallback onOpenTerminal;
  final VoidCallback onDisconnect;
  static const double _headerContentHeight = 114;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = topInset + _headerContentHeight;
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.only(top: headerHeight + 14, bottom: 14),
            children: [
              FlipperPageCard(
                title: 'Firmware Update',
                child: Column(
                  children: [
                    FlipperInfoLine(
                      label: 'Update Channel',
                      value: loading ? 'Loading' : status,
                      valueColor: FlipperOriginalColors.text60,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_controller.svg',
                      label: 'Remote Control',
                      color: FlipperOriginalColors.text100,
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: SvgPicture.asset('assets/flipper_svg/core/ic_navigate.svg'),
                        ),
                      ),
                      onTap: onOpenRemoteControl,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Control your Flipper Zero remotely via mobile phone',
                          style: TextStyle(
                            fontSize: 12,
                            color: FlipperOriginalColors.text30,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Device Info',
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: onOpenFullInfo,
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: SvgPicture.asset('assets/flipper_svg/core/ic_navigate.svg'),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    FlipperInfoLine(label: 'Firmware Version', value: version),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Build Date', value: buildDate),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'Int. Flash (Used/Total)', value: internalFlash),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperInfoLine(label: 'SD Card (Used/Total)', value: sdCard),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_navigate.svg',
                      label: 'Full Info',
                      color: FlipperOriginalColors.blue,
                      onTap: onOpenFullInfo,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_options.svg',
                      label: 'Options',
                      color: FlipperOriginalColors.text100,
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: SvgPicture.asset('assets/flipper_svg/core/ic_navigate.svg'),
                        ),
                      ),
                      onTap: onOpenTerminal,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_syncing.svg',
                      label: 'Synchronize',
                      color: onSynchronize == null
                          ? FlipperOriginalColors.text16
                          : FlipperOriginalColors.blue,
                      onTap: onSynchronize,
                    ),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_ring.svg',
                      label: 'Play Alert on Flipper',
                      color: FlipperOriginalColors.text16,
                      onTap: null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_bluetooth_disable.svg',
                      label: 'Disconnect',
                      color: FlipperOriginalColors.blue,
                      onTap: onDisconnect,
                    ),
                    const Divider(height: 1, color: FlipperOriginalColors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_disconnection.svg',
                      label: 'Forget Flipper',
                      color: FlipperOriginalColors.danger,
                      onTap: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: FlipperOriginalColors.accent,
            padding: EdgeInsets.only(top: topInset),
            height: headerHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
                  child: SizedBox(height: 100, child: const FlipperMockupWidget(active: true)),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: FlipperOriginalColors.card,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Flipper Zero',
                      style: TextStyle(
                        fontSize: 12,
                        color: FlipperOriginalColors.card,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
