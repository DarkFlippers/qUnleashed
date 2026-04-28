import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discovered_device.dart';
import '../services/ble_service.dart';
import '../services/usb_service.dart';
import 'device_info_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen>
    with SingleTickerProviderStateMixin {
  final _ble = BleService();
  final _usb = UsbService();

  late final TabController _tabs;

  List<BleDiscoveredDevice> _bleDevices = [];
  List<UsbDiscoveredDevice> _usbDevices = [];

  StreamSubscription<List<BleDiscoveredDevice>>? _bleSub;
  bool _bleScanning = false;
  bool _usbLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _bleSub = _ble.devicesStream.listen((list) {
      if (mounted) setState(() => _bleDevices = list);
    });
    _refreshUsb();
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _startBleScan() async {
    setState(() { _bleScanning = true; _error = null; _bleDevices = []; });
    final ok = await _ble.requestPermissions();
    if (!ok) {
      setState(() { _bleScanning = false; _error = 'Bluetooth permissions denied'; });
      return;
    }
    await _ble.startScan(timeout: const Duration(seconds: 10));
    if (mounted) setState(() { _bleScanning = false; _bleDevices = _ble.currentDevices; });
  }

  Future<void> _refreshUsb() async {
    setState(() { _usbLoading = true; _error = null; });
    try {
      final list = await _usb.listDevices();
      if (mounted) setState(() { _usbDevices = list; _usbLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _usbLoading = false; _error = 'USB error: $e'; });
    }
  }

  Future<void> _connectTo(DiscoveredDevice dev) async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Connecting…'),
        ]),
      ),
    );
    try {
      final connected = await dev.connect();
      if (!mounted) return;
      Navigator.of(context).pop(); // close dialog
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DeviceInfoScreen(device: connected),
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Connection failed: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qunleashed'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'BLE'),
            Tab(icon: Icon(Icons.usb), text: 'USB'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildBleTab(), _buildUsbTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBleTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _bleScanning ? null : _startBleScan,
              icon: _bleScanning
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_bleScanning ? 'Scanning…' : 'Scan for BLE devices'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ),
        Expanded(
          child: _bleDevices.isEmpty
              ? Center(
                  child: Text(
                    _bleScanning ? 'Searching…' : 'No BLE devices found.\nPress Scan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  itemCount: _bleDevices.length,
                  itemBuilder: (_, i) {
                    final d = _bleDevices[i];
                    return _DeviceTile(
                      icon: Icons.bluetooth,
                      name: d.name,
                      subtitle: '${d.id}   RSSI: ${d.rssi} dBm',
                      onTap: () => _connectTo(d),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUsbTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _usbLoading ? null : _refreshUsb,
              icon: _usbLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(_usbLoading ? 'Refreshing…' : 'Refresh USB devices'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ),
        Expanded(
          child: _usbDevices.isEmpty
              ? Center(
                  child: Text(
                    _usbLoading ? 'Looking…' : 'No USB devices found.\nPlug in a device and press Refresh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  itemCount: _usbDevices.length,
                  itemBuilder: (_, i) {
                    final d = _usbDevices[i];
                    return _DeviceTile(
                      icon: Icons.usb,
                      name: d.name,
                      subtitle: d.id,
                      onTap: () => _connectTo(d),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String subtitle;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFF1E1E1E),
      child: ListTile(
        leading: Icon(icon, color: Colors.orange),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade400)),
        trailing: const Icon(Icons.chevron_right, color: Colors.orange),
        onTap: onTap,
      ),
    );
  }
}
