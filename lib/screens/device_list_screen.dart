import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discovered_device.dart';
import '../services/ble_service.dart';
import '../services/log_service.dart';
import '../services/usb_service.dart';
import '../widgets/flipper_original_ui.dart';
import 'device_info_screen.dart';

bool _isFlipperBle(BleDiscoveredDevice d) {
  final mac = d.id.replaceAll(':', '').toUpperCase();
  return mac.startsWith('80E127') || mac.startsWith('80E126');
}

bool _isFlipperUsb(UsbDiscoveredDevice d) {
  if (d is DesktopUsbDiscoveredDevice) {
    if (d.vendorId == 0x0483) return true;

    final desc = d.description.toLowerCase();
    return desc.contains('stmicroelectronics') ||
        desc.contains('virtual com port') ||
        desc.contains('flipper');
  }
  if (d is AndroidUsbDiscoveredDevice) return d.usbDevice.vid == 0x0483;
  return false;
}

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  FlipperRootTab _tab = FlipperRootTab.device;

  Future<void> _openPicker() async {
    final selected = await showDialog<DiscoveredDevice>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const _DevicePickerDialog(),
    );
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeviceInfoScreen(device: connected)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      LogService.log('[DeviceList] connection failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlipperRootScaffold(
      currentTab: _tab,
      onTabSelected: (tab) => setState(() => _tab = tab),
      deviceIconAsset: 'assets/flipper_svg/connection/ic_no_device_filled.svg',
      deviceLabel: 'No device',
      child: SafeArea(
        child: IndexedStack(
          index: _tab.index,
          children: [
            _DisconnectedDevicePage(onConnect: _openPicker),
            const _PlaceholderPage(title: 'Archive'),
            const _PlaceholderPage(title: 'Apps'),
            const _PlaceholderPage(title: 'Tools'),
          ],
        ),
      ),
    );
  }
}

class _DisconnectedDevicePage extends StatelessWidget {
  const _DisconnectedDevicePage({required this.onConnect});

  final VoidCallback onConnect;

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
                child: SizedBox(
                  height: 100,
                  child: const FlipperMockupWidget(active: false),
                ),
              ),
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'No device',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: FlipperOriginalColors.card,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
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
              const FlipperInfoLine(
                label: 'Update Channel',
                value: 'Connect',
                valueColor: FlipperOriginalColors.text30,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: FlipperOriginalColors.text16,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'UPDATE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const FlipperPageCard(
          title: 'Device Info',
          child: Column(
            children: [
              FlipperInfoLine(label: 'Firmware Version', value: '-'),
              Divider(height: 1, color: FlipperOriginalColors.divider),
              FlipperInfoLine(label: 'Build Date', value: '-'),
              Divider(height: 1, color: FlipperOriginalColors.divider),
              FlipperInfoLine(label: 'SD Card (Used/Total)', value: '-'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FlipperPageCard(
          child: Column(
            children: [
              FlipperActionRow(
                iconAsset: 'assets/flipper_svg/core/ic_bluetooth.svg',
                label: 'Connect',
                color: FlipperOriginalColors.blue,
                onTap: onConnect,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          color: FlipperOriginalColors.text60,
        ),
      ),
    );
  }
}

class _DevicePickerDialog extends StatefulWidget {
  const _DevicePickerDialog();

  @override
  State<_DevicePickerDialog> createState() => _DevicePickerDialogState();
}

class _DevicePickerDialogState extends State<_DevicePickerDialog> {
  final _ble = BleService();
  final _usb = UsbService();

  List<UsbDiscoveredDevice> _usbCache = [];
  StreamSubscription<List<BleDiscoveredDevice>>? _bleSub;
  bool _scanning = false;
  bool _filterEnabled = true;
  List<DiscoveredDevice> _displayed = [];

  @override
  void initState() {
    super.initState();
    _bleSub = _ble.devicesStream.listen(_onBleUpdate);
    _startScan();
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (mounted) setState(() => _scanning = true);
    try {
      _usbCache = await _usb.listDevices();
    } catch (e) {
      LogService.log('[Picker] USB error: $e');
    }
    _rebuild();

    final ok = await _ble.requestPermissions();
    if (!mounted) return;
    if (!ok) {
      setState(() => _scanning = false);
      return;
    }
    await _ble.startScan(timeout: const Duration(seconds: 10));
    if (mounted) setState(() => _scanning = false);
  }

  void _onBleUpdate(List<BleDiscoveredDevice> ble) => _rebuild(bleDevices: ble);

  void _rebuild({List<BleDiscoveredDevice>? bleDevices}) {
    if (!mounted) return;
    final ble = bleDevices ?? _ble.currentDevices;
    List<DiscoveredDevice> all = [..._usbCache, ...ble];
    if (_filterEnabled) {
      all = all.where((d) {
        if (d is BleDiscoveredDevice) return _isFlipperBle(d);
        if (d is UsbDiscoveredDevice) return _isFlipperUsb(d);
        return true;
      }).toList();
    }
    setState(() => _displayed = all);
  }

  void _toggleFilter() {
    _filterEnabled = !_filterEnabled;
    _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select device',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (_scanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.orange),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2C2C2C)),
            Flexible(child: _buildList()),
            const Divider(height: 1, color: Color(0xFF2C2C2C)),
            TextButton(
              onPressed: _toggleFilter,
              child: Text(_filterEnabled ? "Can't find my device" : 'Show only Flipper devices'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_displayed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Text(
          _scanning ? 'Searching for devices...' : 'No Flipper devices found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _displayed.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF2C2C2C), indent: 60),
      itemBuilder: (_, i) => _DeviceListItem(
        device: _displayed[i],
        onTap: () => Navigator.of(context).pop(_displayed[i]),
      ),
    );
  }
}

class _DeviceListItem extends StatelessWidget {
  const _DeviceListItem({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(device.name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(device.id, style: const TextStyle(color: Colors.white70)),
      trailing: Text(
        device.transport == DeviceTransport.ble ? 'BLE' : 'USB',
        style: const TextStyle(color: Colors.white54),
      ),
    );
  }
}
