import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../cancel_spinner.dart';
import '../notification.dart';
import '../../services/connection/link_service.dart';
import '../../services/localization/l10n.dart';
import '../../services/guarded.dart';
import '../../services/logging.dart';
import '../../theme/theme.dart';
import '../../pages/devices/device_scope.dart';
import 'connection_error.dart';

Future<FlipperDevice?> showConnectionDialog(
  BuildContext context, {
  bool usbOnly = false,
}) {
  // Read here rather than inside the dialog: ADR 0011 put the device scope
  // above the Navigator, so every caller of this has one - and the dialog
  // reaching for the global itself was the last thing in `components`
  // resolving its own. ADR 0002.
  final client = DeviceScope.of(context).client;
  return showDialog<FlipperDevice>(
    context: context,
    barrierColor: FlipperOriginalColors.barrier,
    builder: (_) => ConnectionDialog(client: client, usbOnly: usbOnly),
  );
}

/// Picks a device with [showConnectionDialog] and opens its link, reporting
/// a failed attempt with the shared error dialog.
Future<void> promptConnectDevice(BuildContext context) async {
  final selected = await showConnectionDialog(context);
  if (selected == null || !context.mounted) return;
  await connectPickedDevice(context, selected);
}

Future<void> connectPickedDevice(
  BuildContext context,
  FlipperDevice device,
) async {
  try {
    await LinkService.instance.connectDevice(device);
  } catch (e) {
    if (!context.mounted) return;
    await showConnectionFailedDialog(context, e, isBle: device.isBle);
  }
}

/// Opens the link of a connection-list row, reporting a failed attempt with
/// the shared error dialog. A remembered BLE device that stayed silent is not
/// a failure: the row itself shows it as out of range.
Future<void> connectLinkEntry(BuildContext context, LinkEntry entry) async {
  try {
    await LinkService.instance.connect(entry);
  } catch (e) {
    if (!context.mounted) return;
    await showConnectionFailedDialog(context, e, isBle: entry.isBle);
  }
}

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({
    super.key,
    required this.client,
    this.usbOnly = false,
  });

  /// The link this picker scans and connects on.
  final FlipperClient client;

  final bool usbOnly;

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  FlipperClient get _client => widget.client;

  StreamSubscription<List<FlipperDevice>>? _devicesSub;
  StreamSubscription<List<FlipperSessionInfo>>? _sessionsSub;
  bool _scanning = false;
  bool _filterEnabled = true;
  List<FlipperDevice> _displayed = [];
  List<FlipperSessionInfo> _sessions = const [];
  final Set<String> _disconnecting = {};

  @override
  void initState() {
    super.initState();
    _sessions = _client.sessions;
    _devicesSub = _client.devicesStream.listen(_onDevicesUpdate);
    _sessionsSub = _client.sessionsStream.listen(_onSessionsUpdate);
    _displayed = _filterDevices(_client.devices);
    if (!_client.isConnecting) _startScan();
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _sessionsSub?.cancel();
    // Guarded rather than discarded: closing the picker while a scan is
    // failing rejected a future nobody was holding, and that arrives as an
    // unlabelled [uncaught] with no operation on it. #120.
    unawaited(guarded('[Picker] stop scan', _client.stopScan));
    super.dispose();
  }

  static String _keyOf(FlipperDevice device) =>
      '${device.link.name}:${device.id}';

  FlipperSessionInfo? _sessionOf(FlipperDevice device) {
    for (final session in _sessions) {
      if (_keyOf(session.device) == _keyOf(device)) return session;
    }
    return null;
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
      LogService.warn('[Picker] scan error: $e');
      // The list the finally rebuilds is a partial one: refreshDevices
      // clears it and re-adds held sessions and USB devices before the BLE
      // scan that threw, so a short list reads as the whole list - worse
      // than an obviously empty one. Bluetooth off and a busy adapter are
      // both exactly this, and classifyConnectError already has a bucket
      // and a sentence for each. #120.
      if (mounted) {
        await showConnectionFailedDialog(context, e, isBle: !widget.usbOnly);
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _displayed = _filterDevices(_client.devices);
        });
      }
    }
  }

  /// Guarded for the same reason as the one in `dispose`: the future is torn
  /// off into a `VoidCallback`, so a rejection reaches only
  /// `PlatformDispatcher.onError` and arrives in the log as an unlabelled
  /// `[uncaught]` with nothing saying which operation it was. #120.
  void _stopScan() =>
      unawaited(guarded('[Picker] stop scan', _client.stopScan));

  Future<void> _disconnect(FlipperDevice device) async {
    final key = _keyOf(device);
    if (!_disconnecting.add(key)) return;
    setState(() {});
    try {
      await LinkService.instance.disconnectDevice(
        device,
        id: device.id,
        link: device.link,
      );
    } catch (e) {
      LogService.warn('[Picker] disconnect error: $e');
      // The finally below clears the row whatever happened, so the picker
      // shows the device as disconnected while the link may still be up -
      // and the next thing the user does goes to a Flipper they believe
      // they have let go of. As above, the connect dialog is the wrong
      // vocabulary for this. #120.
      if (mounted) {
        context.showNotification(
          context.l10n.fmFailedBecause(
            context.l10n.connectDisconnectFailed(device.name),
            '$e',
          ),
          type: QNotificationType.error,
        );
      }
    } finally {
      _disconnecting.remove(key);
      if (mounted) setState(() {});
    }
  }

  void _onDevicesUpdate(List<FlipperDevice> devices) {
    if (!mounted) return;
    setState(() => _displayed = _filterDevices(devices));
  }

  void _onSessionsUpdate(List<FlipperSessionInfo> sessions) {
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _displayed = _filterDevices(_client.devices);
    });
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
    final listed = {for (final d in result) _keyOf(d)};
    for (final session in _sessions.reversed) {
      final device = session.device;
      if (!(session.connected || session.connecting)) continue;
      if (widget.usbOnly && !device.isUsb) continue;
      if (listed.add(_keyOf(device))) result.insert(0, device);
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
              widget.usbOnly
                  ? context.l10n.pickerSelectUsbDevice
                  : context.l10n.pickerSelectDevice,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.dialogText,
              ),
            ),
          ),
          if (_scanning)
            // The same control as a connecting row carries: a search that
            // cannot be called off left the dialog with a spinner to wait out
            // and a refresh button that only came back once it was over.
            QCancelSpinner(
              onCancel: _stopScan,
              size: 20,
              color: colors.accent,
              tooltip: context.l10n.commonCancel,
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
              ? context.l10n.pickerSearching
              : (widget.usbOnly
                    ? context.l10n.pickerWaitingUsb
                    : context.l10n.pickerNoDevices),
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
        final session = _sessionOf(device);
        final connecting = session?.connecting ?? false;
        final connected = !connecting && (session?.connected ?? false);
        final active = connected && session!.active;
        final held = connected || connecting;
        return _DeviceListItem(
          device: device,
          connected: connected,
          connecting: connecting,
          disconnecting: held && _disconnecting.contains(_keyOf(device)),
          onDisconnect: held ? () => _disconnect(device) : null,
          onTap: active || connecting
              ? null
              : () => Navigator.of(context).pop(device),
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
              child: Text(context.l10n.pickerCantFindDevice),
            )
          : TextButton(
              onPressed: _restoreFilter,
              style: TextButton.styleFrom(foregroundColor: colors.dialogMuted),
              child: Text(context.l10n.pickerShowOnlyDevices),
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

  bool get _held => connected || connecting;

  Widget _buildTrailing(BuildContext context, QAppColors colors) {
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
    if (connecting) return QCancelSpinner(onCancel: onDisconnect);
    return Tooltip(
      message: l10n.pickerDisconnect,
      child: InkResponse(
        onTap: onDisconnect,
        radius: 22,
        child: Icon(Icons.link_off, size: 22, color: colors.danger),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isBle = device.isBle;
    final subtitle = connecting
        ? context.l10n.pickerConnecting
        : connected
        ? context.l10n.connectTapToSwitch
        : (isBle ? device.id : (device.serialNumber ?? device.id));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              isBle
                  ? (_held ? Icons.bluetooth_connected : Icons.bluetooth)
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
                    device.name,
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
            if (_held)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildTrailing(context, colors),
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
