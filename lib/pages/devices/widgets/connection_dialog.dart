import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../theme.dart';

bool _isFlipperBle(FlipperDevice device) {
  final mac = device.id.replaceAll(':', '').toUpperCase();
  return mac.startsWith('80E127') || mac.startsWith('80E126');
}

bool _isFlipperUsb(FlipperDevice device) {
  if (!device.isUsb) return false;
  if (device.vendorId == 0x0483) return true;

  final name = device.name.toLowerCase();
  return name.contains('stmicroelectronics') ||
      name.contains('virtual com port') ||
      name.contains('flipper');
}

Future<FlipperDevice?> showConnectionDialog(
  BuildContext context, {
  bool usbOnly = false,
  bool skipRpc = false,
}) {
  return showDialog<FlipperDevice>(
    context: context,
    barrierColor: FlipperOriginalColors.barrier,
    builder: (_) => ConnectionDialog(
      usbOnly: usbOnly,
      skipRpc: skipRpc,
    ),
  );
}

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({
    super.key,
    this.usbOnly = false,
    this.skipRpc = false,
  });

  final bool usbOnly;
  final bool skipRpc;

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final FlipperClient _client = FlipperOneClient().get();

  StreamSubscription<List<FlipperDevice>>? _devicesSub;
  Timer? _usbPollTimer;
  bool _scanning = false;
  bool _filterEnabled = true;
  List<FlipperDevice> _displayed = [];

  @override
  void initState() {
    super.initState();
    _devicesSub = _client.devicesStream.listen(_onDevicesUpdate);
    _displayed = _filterDevices(_client.devices);
    _startScan();
    _usbPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollUsb(),
    );
  }

  @override
  void dispose() {
    _usbPollTimer?.cancel();
    _devicesSub?.cancel();
    _client.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    if (mounted) setState(() => _scanning = true);
    try {
      await _client.initialize();
      if (widget.usbOnly) {
        await _client.refreshUsbOnly();
      } else {
        await _client.refreshDevices(bleTimeout: const Duration(seconds: 10));
      }
    } catch (e) {
      LogService.log('[Picker] scan error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _displayed = _filterDevices(_client.devices);
        });
      }
    }
  }

  Future<void> _pollUsb() async {
    if (!mounted) return;
    try {
      await _client.refreshUsbOnly();
    } catch (e) {
      LogService.log('[Picker] usb poll error: $e');
    }
    if (!mounted) return;
    setState(() => _displayed = _filterDevices(_client.devices));
  }

  void _onDevicesUpdate(List<FlipperDevice> devices) {
    if (!mounted) return;
    setState(() => _displayed = _filterDevices(devices));
  }

  List<FlipperDevice> _filterDevices(List<FlipperDevice> devices) {
    Iterable<FlipperDevice> filtered = devices;
    if (widget.usbOnly) {
      filtered = filtered.where((d) => d.isUsb);
    }
    if (!_filterEnabled) return filtered.toList();
    return filtered.where((device) {
      if (device.isBle) return _isFlipperBle(device);
      if (device.isUsb) return _isFlipperUsb(device);
      return true;
    }).toList();
  }

  void _removeFilter() {
    setState(() {
      _filterEnabled = false;
      _displayed = _filterDevices(_client.devices);
    });
  }

  void _restoreFilter() {
    setState(() {
      _filterEnabled = true;
      _displayed = _filterDevices(_client.devices);
    });
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
              widget.usbOnly ? 'Select USB device' : 'Select device',
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
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                onPressed: _startScan,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                iconSize: 20,
                color: colors.accent,
                icon: const Icon(Icons.refresh),
              ),
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
          _scanning
              ? 'Searching for devices…'
              : (widget.usbOnly
                  ? 'Waiting for USB connection…'
                  : 'No Flipper devices found.'),
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
  const _DeviceListItem({
    required this.device,
    required this.onTap,
  });

  final FlipperDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isBle = device.isBle;

    final displayName = device.name;
    final subtitle = isBle ? device.id : (device.serialNumber ?? device.id);

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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.dialogText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.dialogMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (device.rssi != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '${device.rssi} dBm',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.dialogMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
