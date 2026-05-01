import 'dart:async';

import 'package:flipperlib/discovered_device.dart';
import 'package:flipperlib/log_service.dart';
import 'package:flutter/material.dart';

import '../../services/ble_service.dart';
import '../../services/usb_service.dart';
import '../../theme.dart';

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
    barrierColor: FlipperOriginalColors.barrier,
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
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.dialogBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Divider(height: 1, color: colors.dialogDivider),
            Flexible(child: _buildList()),
            Divider(height: 1, color: colors.dialogDivider),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Select device',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.dialogText,
              ),
            ),
          ),
          if (_scanning)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.accent,
              ),
            )
          else
            TextButton(
              onPressed: _startScan,
              child: const Text('Search again'),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final colors = context.appColors;
    if (_displayed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Text(
          _scanning ? 'Searching for devices…' : 'No Flipper devices found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.dialogMuted, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _displayed.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: FlipperOriginalColors.dialogDivider,
        indent: 60,
      ),
      itemBuilder: (_, i) => _DeviceListItem(
        device: _displayed[i],
        onTap: () => Navigator.of(context).pop(_displayed[i]),
      ),
    );
  }

  Widget _buildFooter() {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: _filterEnabled
          ? TextButton(
              onPressed: _removeFilter,
              style: TextButton.styleFrom(
                foregroundColor: colors.dialogMuted,
              ),
              child: const Text("Can't find my device"),
            )
          : TextButton(
              onPressed: _restoreFilter,
              style: TextButton.styleFrom(
                foregroundColor: colors.dialogMuted,
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
    final colors = context.appColors;
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
              color: isBle ? colors.info : colors.accent,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colors.dialogText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.dialogMuted,
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
