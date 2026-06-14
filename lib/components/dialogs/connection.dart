import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';

Future<FlipperDevice?> showConnectionDialog(
  BuildContext context, {
  bool usbOnly = false,
  bool skipRpc = false,
}) {
  return showDialog<FlipperDevice>(
    context: context,
    barrierColor: FlipperOriginalColors.barrier,
    builder: (_) => ConnectionDialog(usbOnly: usbOnly, skipRpc: skipRpc),
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
  StreamSubscription<void>? _usbEventsSub;
  StreamSubscription<FlipperConnectionState>? _connSub;
  bool _scanning = false;
  bool _filterEnabled = true;
  List<FlipperDevice> _displayed = [];

  // Active session, tracked live so the connected device's list row can show
  // the connected icon and an inline disconnect button (a proper transport
  // teardown -> GATT disconnect).
  FlipperDevice? _connectedDevice;
  // In-flight connect attempt. A stuck attempt is the state that holds the
  // radio and blocks scanning, so it must be shown here with a cancel action;
  // it is otherwise invisible (no committed session yet).
  FlipperDevice? _connectingDevice;
  bool _disconnecting = false;

  // The device the dialog is bound to right now (committed or in flight). Null
  // when idle.
  FlipperDevice? get _activeDevice => _connectedDevice ?? _connectingDevice;

  @override
  void initState() {
    super.initState();
    _devicesSub = _client.devicesStream.listen(_onDevicesUpdate);
    _connectedDevice = _client.isConnected ? _client.connectedDevice : null;
    _connectingDevice = _client.isConnecting ? _client.connectingDevice : null;
    _connSub = _client.connectionStream.listen(_onConnectionState);
    _displayed = _filterDevices(_client.devices);
    // Only kick off a scan when the radio is free: BLE scans are refused while a
    // connection is active OR in progress, so scanning here would just log "scan
    // skipped" and never surface the device. The live/in-flight device is
    // injected into the list by _filterDevices instead, so its row (with a
    // disconnect/cancel button) shows without needing a scan.
    if (_activeDevice == null && !_client.isConnecting) {
    _startScan();
    }
    // Refresh USB devices on hotplug events instead of polling on a timer.
    _usbEventsSub = _client.usbEvents.listen((_) => _refreshUsb());
  }

  @override
  void dispose() {
    _usbEventsSub?.cancel();
    _devicesSub?.cancel();
    _connSub?.cancel();
    _client.stopScan();
    super.dispose();
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (!mounted) return;
    setState(() {
      if (state.connecting) {
        // Attempt in flight: show it so the user can cancel a stuck connect.
        _connectingDevice = state.device;
      } else if (state.connected) {
        _connectedDevice = state.device ?? _client.connectedDevice;
        _connectingDevice = null;
        _disconnecting = false;
      } else if (!state.reconnecting) {
        // Terminal disconnect (not a transient reconnect): clear everything.
        _connectedDevice = null;
        _connectingDevice = null;
        _disconnecting = false;
      }
      // While reconnecting, keep the last known device so the row stays marked.
      // Recompute the list so the device row appears/disappears live.
      _displayed = _filterDevices(_client.devices);
    });
  }

  Future<void> _disconnect() async {
    if (_disconnecting) return;
    setState(() => _disconnecting = true);
    try {
      // disconnect() runs the single teardown path: it closes the transport,
      // which on BLE issues the real GATT disconnect (cancelPeripheralConnection)
      // instead of just dropping the app-side handle. When a connect is still in
      // flight it also aborts the platform attempt, so a stuck connect tears
      // down now instead of after the full connect timeout.
      await _client.disconnect();
    } catch (e) {
      LogService.log('[Picker] disconnect error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _disconnecting = false;
          _connectedDevice = null;
          _connectingDevice = null;
        });
      }
    }
  }

  bool _isSameDevice(FlipperDevice? a, FlipperDevice b) =>
      a != null && a.link == b.link && a.id == b.id;

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

  Future<void> _refreshUsb() async {
    if (!mounted) return;
    try {
      await _client.refreshUsbOnly();
    } catch (e) {
      LogService.log('[Picker] usb refresh error: $e');
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
    if (_filterEnabled) {
      filtered = filtered.where(_client.isFlipperDevice);
    }
    final result = filtered.toList();
    // Always surface the active device (connected or connect-in-flight), even
    // when it is absent from the scan results — a scan cannot run while the
    // radio is busy. Without this the device would have no row, so there would
    // be no disconnect/cancel button.
    final active = _activeDevice;
    if (active != null &&
        (!widget.usbOnly || active.isUsb) &&
        !result.any((d) => _isSameDevice(active, d))) {
      result.insert(0, active);
    }
    return result;
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
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
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
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: FlipperOriginalColors.dialogDivider),
      itemBuilder: (_, i) {
        final device = _displayed[i];
        final connected = _isSameDevice(_connectedDevice, device);
        final connecting =
            !connected && _isSameDevice(_connectingDevice, device);
        final active = connected || connecting;
        return _DeviceListItem(
          device: device,
          connected: connected,
          connecting: connecting,
          disconnecting: active && _disconnecting,
          // Both states expose teardown: disconnect a live session, or cancel a
          // stuck connect attempt.
          onDisconnect: active ? _disconnect : null,
          // The active row is acted on through its disconnect/cancel button;
          // tapping it to "select" would only kick off a redundant reconnect.
          onTap: active ? null : () => Navigator.of(context).pop(device),
        );
      },
    );
  }

  Widget _buildFooter() {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: _filterEnabled
          ? TextButton(
              onPressed: _removeFilter,
              style: TextButton.styleFrom(foregroundColor: colors.dialogMuted),
              child: const Text("Can't find my device"),
            )
          : TextButton(
              onPressed: _restoreFilter,
              style: TextButton.styleFrom(foregroundColor: colors.dialogMuted),
              child: const Text('Show only Flipper devices'),
            ),
    );
  }
}

class _DeviceListItem extends StatelessWidget {
  const _DeviceListItem({
    required this.device,
    required this.onTap,
    this.connected = false,
    this.connecting = false,
    this.disconnecting = false,
    this.onDisconnect,
  });

  final FlipperDevice device;
  final VoidCallback? onTap;
  final bool connected;
  final bool connecting;
  final bool disconnecting;
  final VoidCallback? onDisconnect;

  bool get _active => connected || connecting;

  // Trailing control for the active row. A bare icon (no IconButton box / hover
  // state-layer) keeps the row the same height as the others, so the separator
  // below is not painted over near the icon.
  Widget _buildTrailing(QAppColors colors) {
    if (disconnecting) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: colors.danger,
        ),
      );
    }
    final label = connecting ? 'Cancel' : 'Disconnect';
    final action = Tooltip(
      message: label,
      child: InkResponse(
        onTap: onDisconnect,
        radius: 20,
        child: Icon(
          connecting ? Icons.close : Icons.link_off,
          size: 22,
          color: colors.danger,
        ),
      ),
    );
    if (!connecting) return action;
    // While connecting, pair a progress spinner with the cancel control so the
    // in-flight attempt reads as active, not already connected.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: colors.info,
          ),
        ),
        const SizedBox(width: 12),
        action,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isBle = device.isBle;

    final displayName = device.name;
    final subtitle = connecting
        ? 'Connecting…'
        : (isBle ? device.id : (device.serialNumber ?? device.id));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              isBle
                  ? (_active ? Icons.bluetooth_connected : Icons.bluetooth)
                  : Icons.usb,
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
                    style: TextStyle(fontSize: 12, color: colors.dialogMuted),
                  ),
                ],
              ),
            ),
            if (_active)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildTrailing(colors),
              )
            else if (device.rssi != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '${device.rssi} dBm',
                  style: TextStyle(fontSize: 12, color: colors.dialogMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
