import 'dart:async';

import 'package:flipperzero/flipperzero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/discovered_device.dart';
import '../services/flipper_protocol.dart';
import '../services/log_service.dart';
import '../widgets/flipper_original_ui.dart';

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
      case Main_Content.systemDeviceInfoResponse:
        final r = msg.systemDeviceInfoResponse;
        _info[r.key] = r.value;
        if (!msg.hasNext) _markDone(msg.commandId);
      case Main_Content.systemPowerInfoResponse:
        final r = msg.systemPowerInfoResponse;
        _info['power.${r.key}'] = r.value;
        if (!msg.hasNext) _markDone(msg.commandId);
      case Main_Content.systemGetDatetimeResponse:
        final dt = msg.systemGetDatetimeResponse.datetime;
        _info['datetime'] =
            '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
        _markDone(msg.commandId);
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
      child: SafeArea(
        child: IndexedStack(
          index: _tab.index,
          children: [
            _ConnectedDevicePage(
              deviceName: widget.device.name,
              status: _status,
              loading: _loading,
              version: _deviceInfoVersion,
              buildDate: _buildDate,
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
              onOpenTerminal: _openTerminal,
              onDisconnect: _disconnect,
            ),
            const Center(child: Text('Archive')),
            const Center(child: Text('Apps')),
            const Center(child: Text('Tools')),
          ],
        ),
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
    required this.sdCard,
    required this.onSynchronize,
    required this.onOpenTerminal,
    required this.onDisconnect,
  });

  final String deviceName;
  final String status;
  final bool loading;
  final String version;
  final String buildDate;
  final String sdCard;
  final VoidCallback? onSynchronize;
  final VoidCallback onOpenTerminal;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Container(
          color: FlipperOriginalColors.accent,
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
        const SizedBox(height: 14),
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
          title: 'Device Info',
          trailing: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 14,
              height: 14,
              child: SvgPicture.asset('assets/flipper_svg/core/ic_navigate.svg'),
            ),
          ),
          child: Column(
            children: [
              FlipperInfoLine(label: 'Firmware Version', value: version),
              const Divider(height: 1, color: FlipperOriginalColors.divider),
              FlipperInfoLine(label: 'Build Date', value: buildDate),
              const Divider(height: 1, color: FlipperOriginalColors.divider),
              FlipperInfoLine(label: 'SD Card (Used/Total)', value: sdCard),
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
                iconAsset: 'assets/flipper_svg/info/ic_controller.svg',
                label: 'Remote Control',
                color: FlipperOriginalColors.blue,
                onTap: onOpenTerminal,
              ),
              const Divider(height: 1, color: FlipperOriginalColors.divider),
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
        const SizedBox(height: 14),
      ],
    );
  }
}
