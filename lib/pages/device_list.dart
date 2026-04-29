import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flipperzero/flipperzero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/discovered_device.dart';
import '../services/flipper_protocol.dart';
import '../services/log_service.dart';
import '../widgets/device_shell.dart';
import 'widgets/connection.dart';
import 'remote_control.dart';

// =============================================================================
// Root screen — manages disconnected / connected state inline (no navigation)
// =============================================================================

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  FlipperRootTab _tab = FlipperRootTab.device;

  // --- connection ---
  ConnectedDevice? _device;
  bool _deviceDisconnected = false;

  // --- device info ---
  Map<String, String> _info = {};
  final List<String> _logs = [];
  FlipperFrameBuffer _buf = FlipperFrameBuffer();
  Set<int> _pending = {};
  String _deviceStatus = '';
  bool _deviceLoading = false;

  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<String>? _logSub;
  Timer? _timeoutTimer;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _cleanupDevice(disconnect: true);
    super.dispose();
  }

  void _cleanupDevice({required bool disconnect}) {
    _timeoutTimer?.cancel();
    _logSub?.cancel();
    _dataSub?.cancel();
    if (disconnect && !_deviceDisconnected) _device?.disconnect();
  }

  // -------------------------------------------------------------------------
  // Connection
  // -------------------------------------------------------------------------

  Future<void> _openPicker() async {
    final selected = await showConnectionDialog(context);
    if (selected != null && mounted) _connectTo(selected);
  }

  Future<void> _connectTo(DiscoveredDevice dev) async {
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
      final connected = await dev.connect();
      if (!mounted) return;
      Navigator.of(context).pop();
      _setupDevice(connected);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      LogService.log('[DeviceList] connection failed: $e');
    }
  }

  void _setupDevice(ConnectedDevice connected) {
    _cleanupDevice(disconnect: false);
    setState(() {
      _device = connected;
      _deviceDisconnected = false;
      _info = {};
      _buf = FlipperFrameBuffer();
      _pending = {};
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
        LogService.log('[DeviceList] stream error: $e');
        if (!mounted) return;
        setState(() { _deviceStatus = 'Connection failed'; _deviceLoading = false; });
      },
      onDone: () {
        LogService.log('[DeviceList] stream closed');
        if (!mounted) return;
        setState(() { _deviceStatus = 'Disconnected'; _deviceDisconnected = true; _deviceLoading = false; });
      },
    );

    _initDevice(connected);
  }

  Future<void> _initDevice(ConnectedDevice connected) async {
    try {
      await connected.init();
    } catch (e) {
      LogService.log('[DeviceList] init error: $e');
      if (!mounted) return;
      setState(() { _deviceStatus = 'Initialization failed'; _deviceLoading = false; });
      return;
    }
    if (mounted) setState(() => _deviceStatus = 'Requesting device info...');
    await _requestAll(connected);
  }

  Future<void> _requestAll(ConnectedDevice connected) async {
    try {
      final protoId = FlipperProtocol.nextCommandId();
      _pending.add(protoId);
      await connected.sendBytes(FlipperProtocol.encode(
        Main(commandId: protoId, systemProtobufVersionRequest: ProtobufVersionRequest()),
      ));

      final devId = FlipperProtocol.nextCommandId();
      _pending.add(devId);
      await connected.sendBytes(FlipperProtocol.encode(
        Main(commandId: devId, systemDeviceInfoRequest: DeviceInfoRequest()),
      ));

      final pwrId = FlipperProtocol.nextCommandId();
      _pending.add(pwrId);
      await connected.sendBytes(FlipperProtocol.encode(
        Main(commandId: pwrId, systemPowerInfoRequest: PowerInfoRequest()),
      ));

      final dtId = FlipperProtocol.nextCommandId();
      _pending.add(dtId);
      await connected.sendBytes(FlipperProtocol.encode(
        Main(commandId: dtId, systemGetDatetimeRequest: GetDateTimeRequest()),
      ));

      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted || !_deviceLoading) return;
        setState(() {
          _deviceStatus = _info.isEmpty ? 'Timeout — no response' : 'Timeout — partial data';
          _deviceLoading = false;
        });
      });
    } catch (e) {
      LogService.log('[DeviceList] send error: $e');
      if (!mounted) return;
      setState(() { _deviceStatus = 'Request failed'; _deviceLoading = false; });
    }
  }

  // -------------------------------------------------------------------------
  // Protobuf message handling
  // -------------------------------------------------------------------------

  void _onData(List<int> raw) {
    final messages = _buf.push(raw);
    for (final msg in messages) {
      if (mounted) setState(() => _handleMessage(msg));
    }
  }

  void _handleMessage(Main msg) {
    if (msg.commandStatus == CommandStatus.ERROR_DECODE) {
      if (msg.commandId == 0 && _pending.isNotEmpty) { _pending.clear(); _checkDone(); }
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
            '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';
        _markDone(msg.commandId);
        break;
      default:
        break;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
  void _markDone(int id) { _pending.remove(id); _checkDone(); }
  void _checkDone() {
    if (_pending.isEmpty && _deviceLoading) {
      _timeoutTimer?.cancel();
      _deviceStatus = 'Connected';
      _deviceLoading = false;
    }
  }

  // -------------------------------------------------------------------------
  // Device info getters
  // -------------------------------------------------------------------------

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
    for (final k in keys) {
      final v = _info[k];
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return fallback;
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _disconnect() async {
    _timeoutTimer?.cancel();
    _deviceDisconnected = true;
    await _device?.disconnect();
    if (mounted) setState(() { _device = null; _deviceDisconnected = false; });
  }

  Future<void> _openRemoteControl() async {
    final dev = _device;
    if (dev == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RemoteControlScreen(device: dev)),
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
                  width: 44, height: 4,
                  decoration: BoxDecoration(
                    color: FlipperOriginalColors.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text('Full Info',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: FlipperOriginalColors.text100)),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Firmware',
                child: Column(children: [
                  FlipperInfoLine(label: 'Firmware Version', value: _deviceFirmwareVersion),
                  const Divider(height: 1, color: FlipperOriginalColors.divider),
                  FlipperInfoLine(label: 'Build Date', value: _buildDate),
                  const Divider(height: 1, color: FlipperOriginalColors.divider),
                  FlipperInfoLine(label: 'SD Card (Used/Total)', value: _sdCard),
                  const Divider(height: 1, color: FlipperOriginalColors.divider),
                  FlipperInfoLine(label: 'Int. Flash (Used/Total)', value: _internalFlash),
                ]),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Raw Data',
                child: _info.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No data received.',
                          style: TextStyle(fontSize: 14, color: FlipperOriginalColors.text30)),
                      )
                    : Column(
                        children: [
                          for (final e in (_info.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                            Column(children: [
                              FlipperInfoLine(label: e.key, value: e.value),
                              const Divider(height: 1, color: FlipperOriginalColors.divider),
                            ]),
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
          width: 900, height: 560,
          child: Column(children: [
            Container(
              color: const Color(0xFF151515),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                const Text('Terminal',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed: () => setState(_logs.clear), child: const Text('Clear')),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ]),
            ),
            Expanded(
              child: _logs.isEmpty
                  ? const Center(child: Text('No logs yet.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Text(_logs[i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: Color(0xFF90EE90))),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

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
              ? _ConnectedDevicePage(
                  deviceName: _deviceName,
                  status: _deviceStatus,
                  infoLoading: _deviceLoading,
                  deviceFirmwareVersion: _deviceFirmwareVersion,
                  buildDate: _buildDate,
                  internalFlash: _internalFlash,
                  sdCard: _sdCard,
                  onSynchronize: _deviceLoading
                      ? null
                      : () {
                          setState(() {
                            _deviceLoading = true;
                            _deviceStatus = 'Refreshing...';
                            _pending.clear();
                            _info.clear();
                          });
                          _requestAll(device);
                        },
                  onOpenRemoteControl: _openRemoteControl,
                  onOpenFullInfo: _openFullInfo,
                  onOpenTerminal: _openTerminal,
                  onDisconnect: _disconnect,
                )
              : _DisconnectedDevicePage(onConnect: _openPicker),
          const _PlaceholderPage(title: 'Archive'),
          const _PlaceholderPage(title: 'Apps'),
          const _PlaceholderPage(title: 'Tools'),
        ],
      ),
    );
  }
}

// =============================================================================
// Disconnected page
// =============================================================================

class _DisconnectedDevicePage extends StatelessWidget {
  const _DisconnectedDevicePage({required this.onConnect});

  final VoidCallback onConnect;
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
              const _FirmwareCarouselCard(deviceVersion: null),
              const SizedBox(height: 14),
              const FlipperPageCard(
                title: 'Device Info',
                child: Column(children: [
                  FlipperInfoLine(label: 'Firmware Version', value: '-'),
                  Divider(height: 1, color: FlipperOriginalColors.divider),
                  FlipperInfoLine(label: 'Build Date', value: '-'),
                  Divider(height: 1, color: FlipperOriginalColors.divider),
                  FlipperInfoLine(label: 'SD Card (Used/Total)', value: '-'),
                ]),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(children: [
                  FlipperActionRow(
                    iconAsset: 'assets/flipper_svg/core/ic_bluetooth.svg',
                    label: 'Connect',
                    color: FlipperOriginalColors.blue,
                    onTap: onConnect,
                  ),
                ]),
              ),
            ],
          ),
        ),
        _Header(
          topInset: topInset,
          headerHeight: headerHeight,
          title: 'No device',
          subtitle: 'Flipper Zero',
          active: false,
        ),
      ],
    );
  }
}

// =============================================================================
// Connected page
// =============================================================================

class _ConnectedDevicePage extends StatelessWidget {
  const _ConnectedDevicePage({
    required this.deviceName,
    required this.status,
    required this.infoLoading,
    required this.deviceFirmwareVersion,
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
  final bool infoLoading;
  final String deviceFirmwareVersion;
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
              // — Firmware carousel, now aware of device version —
              _FirmwareCarouselCard(
                deviceVersion: infoLoading ? null : deviceFirmwareVersion,
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(children: [
                  FlipperActionRow(
                    iconAsset: 'assets/flipper_svg/info/ic_controller.svg',
                    label: 'Remote Control',
                    color: FlipperOriginalColors.text100,
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 14, height: 14,
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
                        style: TextStyle(fontSize: 12, color: FlipperOriginalColors.text30),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Device Info',
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: onOpenFullInfo,
                    child: SizedBox(
                      width: 14, height: 14,
                      child: SvgPicture.asset('assets/flipper_svg/core/ic_navigate.svg'),
                    ),
                  ),
                ),
                child: Column(children: [
                  FlipperInfoLine(label: 'Firmware Version', value: deviceFirmwareVersion),
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
                ]),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(children: [
                  FlipperActionRow(
                    iconAsset: 'assets/flipper_svg/info/ic_options.svg',
                    label: 'Options',
                    color: FlipperOriginalColors.text100,
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 14, height: 14,
                        child: SvgPicture.asset('assets/flipper_svg/core/ic_navigate.svg'),
                      ),
                    ),
                    onTap: onOpenTerminal,
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(children: [
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
                ]),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(children: [
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
                ]),
              ),
            ],
          ),
        ),
        _Header(
          topInset: topInset,
          headerHeight: headerHeight,
          title: deviceName,
          subtitle: 'Flipper Zero',
          active: true,
        ),
      ],
    );
  }
}

// =============================================================================
// Shared header widget
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({
    required this.topInset,
    required this.headerHeight,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final double topInset;
  final double headerHeight;
  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        color: FlipperOriginalColors.accent,
        padding: EdgeInsets.only(top: topInset),
        height: headerHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
              child: SizedBox(height: 100, child: FlipperMockupWidget(active: active)),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: FlipperOriginalColors.card)),
                const SizedBox(height: 3),
                Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: FlipperOriginalColors.card)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Firmware carousel card
// =============================================================================

const _kFirmwareApiUrl = 'https://update.flipperzero.one/firmware/directory.json';

class _FirmwareOption {
  final String name;
  final String assetPath;
  const _FirmwareOption(this.name, this.assetPath);
}

const _kFirmwares = [
  _FirmwareOption('Unleashed', 'assets/firmware/unleashed.png'),
  _FirmwareOption('Flipper', 'assets/firmware/flipper.png'),
  _FirmwareOption('Momentum', 'assets/firmware/momentum.png'),
  _FirmwareOption('RogueMaster', 'assets/firmware/master.png'),
  _FirmwareOption('Chronos', 'assets/firmware/chronos.png'),
];

/// [deviceVersion] — версия прошивки на устройстве.
/// null  = нет устройства (disconnected)
/// '-'   = устройство подключено, данные ещё загружаются
/// 'X.Y' = реальная версия
class _FirmwareCarouselCard extends StatefulWidget {
  const _FirmwareCarouselCard({required this.deviceVersion});

  final String? deviceVersion;

  @override
  State<_FirmwareCarouselCard> createState() => _FirmwareCarouselCardState();
}

class _FirmwareCarouselCardState extends State<_FirmwareCarouselCard> {
  final _controller = PageController();
  int _page = 0;
  String? _latestVersion; // fetched from server
  bool _fetchLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchVersion();
  }

  Future<void> _fetchVersion() async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(_kFirmwareApiUrl));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      final channels = data['channels'] as List<dynamic>;

      String? version;
      int latestTs = -1;
      for (final ch in channels) {
        if (ch['id'] == 'release') {
          for (final v in ch['versions'] as List<dynamic>) {
            final ts = (v['timestamp'] as num).toInt();
            if (ts > latestTs) {
              latestTs = ts;
              version = v['version'] as String;
            }
          }
        }
      }
      if (mounted) setState(() { _latestVersion = version; _fetchLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _fetchLoading = false; });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlipperPageCard(
      title: 'Firmware Update',
      child: Column(
        children: [
          // — Carousel slides —
          SizedBox(
            height: 80,
            child: PageView.builder(
              controller: _controller,
              itemCount: _kFirmwares.length,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (_, i) => _FirmwareSlide(
                option: _kFirmwares[i],
                latestVersion: _latestVersion,
                fetchLoading: _fetchLoading,
              ),
            ),
          ),

          // — Dot indicators —
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_kFirmwares.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 8 : 5,
                  height: active ? 8 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? FlipperOriginalColors.accent : FlipperOriginalColors.text16,
                  ),
                );
              }),
            ),
          ),

          // — Action button —
          _FirmwareButton(
            fetchLoading: _fetchLoading,
            latestVersion: _latestVersion,
            deviceVersion: widget.deviceVersion,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Single carousel slide
// =============================================================================

class _FirmwareSlide extends StatelessWidget {
  const _FirmwareSlide({
    required this.option,
    required this.latestVersion,
    required this.fetchLoading,
  });

  final _FirmwareOption option;
  final String? latestVersion;
  final bool fetchLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(option.assetPath, width: 62, height: 62, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.name,
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: FlipperOriginalColors.accent),
                ),
                const SizedBox(height: 2),
                Text(
                  fetchLoading ? 'Checking…' : (latestVersion ?? '—'),
                  style: const TextStyle(fontSize: 12, color: FlipperOriginalColors.text30),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Firmware action button
//
// Button states (mirrors original Flipper app UpdateCardState logic):
//   fetchLoading                          → orange  INSTALL  "Checking for updates…"
//   latestVersion == null  (server error) → orange  INSTALL  "Can't connect to update server"
//   deviceVersion == null  (disconnected) → orange  INSTALL  "…will be installed"
//   deviceVersion == latestVersion        → gray    NO UPDATES  "There are no updates…"
//   deviceVersion != latestVersion        → green   UPDATE      "Update Flipper to the latest version"
// =============================================================================

const _kFlipperBold = TextStyle(
  fontFamily: 'FlipperBold',
  fontSize: 40,
  fontWeight: FontWeight.w500,
  color: Colors.white,
);

class _FirmwareButton extends StatelessWidget {
  const _FirmwareButton({
    required this.fetchLoading,
    required this.latestVersion,
    required this.deviceVersion,
  });

  final bool fetchLoading;
  final String? latestVersion;

  /// null  = no device (disconnected)
  /// '-'   = device connected, info still loading
  /// 'X.Y' = actual device firmware version
  final String? deviceVersion;

  @override
  Widget build(BuildContext context) {
    final _ButtonState state = _resolve();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        children: [
          GestureDetector(
            onTap: state.enabled ? () {} : null,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: state.color,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(state.label, style: _kFlipperBold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              state.description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: FlipperOriginalColors.text30),
            ),
          ),
        ],
      ),
    );
  }

  _ButtonState _resolve() {
    // Server still fetching
    if (fetchLoading) {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Checking for updates…',
        enabled: false,
      );
    }

    // Server fetch failed
    if (latestVersion == null) {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Can\'t connect to update server',
        enabled: false,
      );
    }

    // No device connected
    if (deviceVersion == null) {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Firmware on Flipper doesn\'t match the selected update channel.\nSelected version will be installed.',
        enabled: true,
      );
    }

    // Device info still loading (deviceVersion == '-')
    if (deviceVersion == '-') {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Checking device firmware version…',
        enabled: false,
      );
    }

    // Compare versions
    if (deviceVersion == latestVersion) {
      return _ButtonState(
        label: 'NO UPDATES',
        color: FlipperOriginalColors.text16,
        description: 'There are no updates in the selected channel',
        enabled: false,
      );
    }

    return _ButtonState(
      label: 'UPDATE',
      color: FlipperOriginalColors.green,
      description: 'Update Flipper to the latest version',
      enabled: true,
    );
  }
}

class _ButtonState {
  final String label;
  final Color color;
  final String description;
  final bool enabled;
  const _ButtonState({
    required this.label,
    required this.color,
    required this.description,
    required this.enabled,
  });
}

// =============================================================================
// Placeholder tabs
// =============================================================================

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title,
        style: const TextStyle(fontSize: 20, color: FlipperOriginalColors.text60)),
    );
  }
}
