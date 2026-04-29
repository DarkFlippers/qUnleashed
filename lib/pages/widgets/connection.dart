import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/discovered_device.dart';
import '../../services/ble_service.dart';
import '../../services/log_service.dart';
import '../../services/usb_service.dart';

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

Future<DiscoveredDevice?> showConnectionDialog(BuildContext context) {
  return showDialog<DiscoveredDevice>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const ConnectionDialog(),
  );
}

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
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

  void _removeFilter() {
    _filterEnabled = false;
    _rebuild();
  }

  void _restoreFilter() {
    _filterEnabled = true;
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
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFF2C2C2C)),
            Flexible(child: _buildList()),
            const Divider(height: 1, color: Color(0xFF2C2C2C)),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
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
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.orange,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_displayed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Text(
          _scanning ? 'Searching for devices…' : 'No Flipper devices found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _displayed.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: Color(0xFF2C2C2C),
        indent: 60,
      ),
      itemBuilder: (_, i) => _DeviceListItem(
        device: _displayed[i],
        onTap: () => Navigator.of(context).pop(_displayed[i]),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: _filterEnabled
          ? TextButton(
              onPressed: _removeFilter,
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade500,
              ),
              child: const Text("Can't find my device"),
            )
          : TextButton(
              onPressed: _restoreFilter,
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade500,
              ),
              child: const Text('Show only Flipper devices'),
            ),
    );
  }
}

class _DeviceListItem extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onTap;

  const _DeviceListItem({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBle = device.transport == DeviceTransport.ble;

    String displayName;
    String subtitle;

    if (device is BleDiscoveredDevice) {
      final d = device as BleDiscoveredDevice;
      displayName = d.name;
      subtitle = d.id;
    } else if (device is DesktopUsbDiscoveredDevice) {
      final d = device as DesktopUsbDiscoveredDevice;
      displayName = d.description.isNotEmpty ? d.description : d.portName;
      subtitle = d.serialNumber ?? d.portName;
    } else {
      displayName = device.name;
      subtitle = device.id;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              isBle ? Icons.bluetooth : Icons.usb,
              color: isBle ? Colors.blue.shade300 : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
