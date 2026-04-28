import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flipperzero/flipperzero.dart';

import '../models/discovered_device.dart';
import '../services/flipper_protocol.dart';
import '../services/log_service.dart';

class DeviceInfoScreen extends StatefulWidget {
  final ConnectedDevice device;
  const DeviceInfoScreen({super.key, required this.device});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  final Map<String, String> _info = {};

  String _status = 'Initializing…';
  bool _loading = true;
  bool _disconnected = false;

  StreamSubscription<List<int>>? _dataSub;
  final _buf = FlipperFrameBuffer();

  final Set<int> _pending = {};
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    // 1. Data subscription
    _dataSub = widget.device.dataStream.listen(
      _onData,
      onError: (e) {
        LogService.log('[DeviceInfo] stream error: $e');
        if (mounted) setState(() { _status = 'Connection failed'; _loading = false; });
      },
      onDone: () {
        LogService.log('[DeviceInfo] stream closed');
        if (mounted) setState(() { _status = 'Disconnected'; _disconnected = true; _loading = false; });
      },
    );

    // 2. Init then request (async, so build() runs first)
    _initAndRequest();
  }

  Future<void> _initAndRequest() async {
    try {
      await widget.device.init();
    } catch (e) {
      LogService.log('[DeviceInfo] init error: $e');
      if (mounted) {
        setState(() {
          _status = 'Initialization failed';
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _status = 'Requesting device info…');
    await _requestAll();
  }

  Future<void> _requestAll() async {
    try {
      final protoId = FlipperProtocol.nextCommandId();
      _pending.add(protoId);
      await widget.device.sendBytes(FlipperProtocol.encode(
          Main(commandId: protoId, systemProtobufVersionRequest: ProtobufVersionRequest())));

      final devId = FlipperProtocol.nextCommandId();
      _pending.add(devId);
      await widget.device.sendBytes(FlipperProtocol.encode(
          Main(commandId: devId, systemDeviceInfoRequest: DeviceInfoRequest())));

      final pwrId = FlipperProtocol.nextCommandId();
      _pending.add(pwrId);
      await widget.device.sendBytes(FlipperProtocol.encode(
          Main(commandId: pwrId, systemPowerInfoRequest: PowerInfoRequest())));

      final dtId = FlipperProtocol.nextCommandId();
      _pending.add(dtId);
      await widget.device.sendBytes(FlipperProtocol.encode(
          Main(commandId: dtId, systemGetDatetimeRequest: GetDateTimeRequest())));

      LogService.log('[DeviceInfo] sent ${_pending.length} requests, pending: $_pending');

      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (mounted && _loading) {
          LogService.log('[DeviceInfo] timeout — pending=$_pending');
          setState(() {
            _status = _info.isEmpty
                ? 'Timeout — no response from device'
                : 'Timeout — partial data for ${widget.device.name}';
            _loading = false;
          });
        }
      });
    } catch (e) {
      LogService.log('[DeviceInfo] send error: $e');
      if (mounted) setState(() { _status = 'Request failed'; _loading = false; });
    }
  }

  void _onData(List<int> raw) {
    final hex = raw.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    LogService.log('[DeviceInfo] raw ${raw.length} bytes: $hex');
    final messages = _buf.push(raw);
    for (final msg in messages) {
      LogService.log('[DeviceInfo] msg cmd=${msg.commandId} '
          'status=${msg.commandStatus.name} '
          'hasNext=${msg.hasNext} '
          'content=${msg.whichContent().name}');
      if (mounted) setState(() => _handleMessage(msg));
    }
  }

  void _handleMessage(Main msg) {
    // ERROR_DECODE: Flipper couldn't parse our message.
    // Log it, clear the corresponding pending entry if possible, and continue.
    if (msg.commandStatus == CommandStatus.ERROR_DECODE) {
      LogService.log('[DeviceInfo] ERROR_DECODE from device — possible protocol mismatch');
      // commandId=0 means Flipper doesn't know which command failed;
      // remove all pending to avoid infinite wait only if nothing else expected.
      if (msg.commandId == 0 && _pending.isNotEmpty) {
        LogService.log('[DeviceInfo] clearing all pending due to ERROR_DECODE');
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
        _info['datetime'] = '${dt.year}-${_p(dt.month)}-${_p(dt.day)}'
            ' ${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';
        _markDone(msg.commandId);

      case Main_Content.systemPingResponse:
        LogService.log('[DeviceInfo] pong');

      default:
        LogService.log('[DeviceInfo] unhandled content: ${msg.whichContent().name}');
    }
  }

  void _markDone(int commandId) {
    _pending.remove(commandId);
    LogService.log('[DeviceInfo] cmd $commandId done, pending=${_pending.length}');
    _checkDone();
  }

  void _checkDone() {
    if (_pending.isEmpty && _loading) {
      _timeoutTimer?.cancel();
      _status = 'Connected — ${widget.device.name}';
      _loading = false;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  @override
  void dispose() {
    _timeoutTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final entries = _info.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(
            status: _status,
            loading: _loading,
            disconnected: _disconnected,
            transport: widget.device.transport,
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.orange)
                        : Text('No data received.',
                            style: TextStyle(color: Colors.grey.shade500)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: entries.length,
                    itemBuilder: (_, i) =>
                        _InfoRow(k: entries[i].key, v: entries[i].value),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String status;
  final bool loading, disconnected;
  final DeviceTransport transport;
  const _StatusBar(
      {required this.status,
      required this.loading,
      required this.disconnected,
      required this.transport});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF202020),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(children: [
        if (loading) ...[
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 8),
        ],
        Expanded(
            child: Text(status,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
        Text(transport == DeviceTransport.ble ? 'BLE' : 'USB',
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String k, v;
  const _InfoRow({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 180,
            child: Text(k,
                style: TextStyle(
                    color: Colors.orange.shade300,
                    fontFamily: 'monospace',
                    fontSize: 12))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(v,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace', fontSize: 12))),
      ]),
    );
  }
}
