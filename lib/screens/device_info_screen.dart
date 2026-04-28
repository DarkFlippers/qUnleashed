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
  final List<String> _logs = [];

  String _status = 'Requesting device info…';
  bool _loading = true;
  bool _disconnected = false;

  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<String>? _logSub;
  final FlipperFrameBuffer _buf = FlipperFrameBuffer();

  // Pending: set of command IDs we're waiting on
  final Set<int> _pending = {};
  Timer? _timeoutTimer;

  final _logScrollCtrl = ScrollController();
  final _infoScrollCtrl = ScrollController();

  // Show logs panel by default
  bool _showLogs = true;

  @override
  void initState() {
    super.initState();

    // Subscribe to global log stream
    _logSub = LogService.stream.listen((line) {
      if (!mounted) return;
      setState(() => _logs.add(line));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollCtrl.hasClients) {
          _logScrollCtrl.jumpTo(_logScrollCtrl.position.maxScrollExtent);
        }
      });
    });

    // Subscribe to device data
    _dataSub = widget.device.dataStream.listen(
      _onData,
      onError: (e) {
        LogService.log('[DeviceInfo] stream error: $e');
        if (mounted) setState(() { _status = 'Stream error: $e'; _loading = false; });
      },
      onDone: () {
        LogService.log('[DeviceInfo] stream closed');
        if (mounted) setState(() { _status = 'Disconnected'; _disconnected = true; _loading = false; });
      },
    );

    _requestAll();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _logSub?.cancel();
    _dataSub?.cancel();
    _logScrollCtrl.dispose();
    _infoScrollCtrl.dispose();
    if (!_disconnected) widget.device.disconnect();
    super.dispose();
  }

  Future<void> _requestAll() async {
    try {
      // Ping first to verify RPC channel is alive
      final pingId = FlipperProtocol.nextCommandId();
      await widget.device.sendBytes(
          FlipperProtocol.encode(Main(
            commandId: pingId, hasNext: false,
            systemPingRequest: PingRequest(data: [0xDE, 0xAD]),
          )));
      await Future.delayed(const Duration(milliseconds: 300));

      final protoId = FlipperProtocol.nextCommandId();
      _pending.add(protoId);
      await widget.device.sendBytes(
          FlipperProtocol.encode(Main(
            commandId: protoId, hasNext: false,
            systemProtobufVersionRequest: ProtobufVersionRequest(),
          )));

      final devId = FlipperProtocol.nextCommandId();
      _pending.add(devId);
      await widget.device.sendBytes(
          FlipperProtocol.encode(Main(
            commandId: devId, hasNext: false,
            systemDeviceInfoRequest: DeviceInfoRequest(),
          )));

      final pwrId = FlipperProtocol.nextCommandId();
      _pending.add(pwrId);
      await widget.device.sendBytes(
          FlipperProtocol.encode(Main(
            commandId: pwrId, hasNext: false,
            systemPowerInfoRequest: PowerInfoRequest(),
          )));

      final dtId = FlipperProtocol.nextCommandId();
      _pending.add(dtId);
      await widget.device.sendBytes(
          FlipperProtocol.encode(Main(
            commandId: dtId, hasNext: false,
            systemGetDatetimeRequest: GetDateTimeRequest(),
          )));

      // Timeout: after 10 seconds show whatever we have
      _timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _loading) {
          LogService.log('[DeviceInfo] timeout — showing partial data');
          setState(() {
            _status = 'Timeout — showing partial data for ${widget.device.name}';
            _loading = false;
          });
        }
      });
    } catch (e) {
      LogService.log('[DeviceInfo] send error: $e');
      if (mounted) setState(() { _status = 'Send error: $e'; _loading = false; });
    }
  }

  void _onData(List<int> raw) {
    LogService.log('[DeviceInfo] raw ${raw.length} bytes');
    final messages = _buf.push(raw);
    for (final msg in messages) {
      LogService.log('[DeviceInfo] parsed cmd=${msg.commandId} '
          'status=${msg.commandStatus} content=${msg.whichContent()}');
      if (mounted) setState(() => _handleMessage(msg));
    }
  }

  void _handleMessage(Main msg) {
    switch (msg.whichContent()) {
      case Main_Content.systemPingResponse:
        LogService.log('[DeviceInfo] pong OK');

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
            '${dt.year}-${_p(dt.month)}-${_p(dt.day)} '
            '${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';
        _markDone(msg.commandId);

      default:
        LogService.log('[DeviceInfo] unhandled: ${msg.whichContent()}');
    }
  }

  void _markDone(int commandId) {
    _pending.remove(commandId);
    LogService.log('[DeviceInfo] command $commandId done, pending=${_pending.length}');
    if (_pending.isEmpty && _loading) {
      _timeoutTimer?.cancel();
      _status = 'Connected — ${widget.device.name}';
      _loading = false;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _disconnect() async {
    _timeoutTimer?.cancel();
    await widget.device.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _info.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          IconButton(
            icon: Icon(_showLogs ? Icons.terminal : Icons.terminal_outlined),
            tooltip: _showLogs ? 'Hide logs' : 'Show logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _StatusBar(
            status: _status,
            loading: _loading,
            disconnected: _disconnected,
            transport: widget.device.transport,
          ),

          // Device info
          Expanded(
            flex: _showLogs ? 1 : 2,
            child: entries.isEmpty
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.orange)
                        : Text('No data received.',
                            style: TextStyle(color: Colors.grey.shade500)),
                  )
                : ListView.builder(
                    controller: _infoScrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _InfoRow(
                      k: entries[i].key,
                      v: entries[i].value,
                    ),
                  ),
          ),

          // Log panel
          if (_showLogs) ...[
            const Divider(height: 1, color: Colors.orange),
            Container(
              color: const Color(0xFF0A0A0A),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  const Text('Logs', style: TextStyle(color: Colors.orange, fontSize: 12)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _logs.clear()),
                    child: const Text('clear',
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: _logs.isEmpty
                  ? const Center(
                      child: Text('No logs yet.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    )
                  : ListView.builder(
                      controller: _logScrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Text(
                        _logs[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF90EE90),
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String status;
  final bool loading;
  final bool disconnected;
  final DeviceTransport transport;

  const _StatusBar({
    required this.status,
    required this.loading,
    required this.disconnected,
    required this.transport,
  });

  @override
  Widget build(BuildContext context) {
    final color = loading
        ? Colors.orange.shade900
        : disconnected
            ? Colors.red.shade900
            : Colors.green.shade900;

    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(status,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          Text(
            transport == DeviceTransport.ble ? 'BLE' : 'USB',
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String k;
  final String v;
  const _InfoRow({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(k,
                style: TextStyle(
                    color: Colors.orange.shade300,
                    fontFamily: 'monospace',
                    fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
