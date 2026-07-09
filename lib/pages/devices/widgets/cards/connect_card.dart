import 'package:flutter/material.dart';

import '../../../../components/dialogs/connection.dart';
import '../../../../components/dialogs/connection_error.dart';
import '../../../../services/connection/known_devices.dart';
import '../../../../theme/theme.dart';
import '../../../../widgets/page_card.dart';
import '../../controllers/device.dart';
import '../../device_scope.dart';

class ConnectCard extends StatelessWidget {
  const ConnectCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = DeviceScope.of(context);
    final colors = context.appColors;
    final known = ctrl.knownDevices;
    final usb = ctrl.usbSessions;

    return FlipperPageCard(
      child: Column(
        children: [
          _ConnectActionRow(
            color: colors.accent,
            onTap: () => _openPicker(context),
          ),
          for (final session in usb) ...[
            Divider(height: 1, color: colors.divider),
            _DeviceRow(
              name: session.device.name,
              isUsb: true,
              online: true,
              active: session.active,
              sessionConnected: session.connected,
              busy: false,
              onTap: () => ctrl.activateSession(session.device),
              onDisconnect: () => ctrl.disconnectSession(session.device),
            ),
          ],
          for (var i = 0; i < known.length; i++) ...[
            Divider(height: 1, color: colors.divider),
            _DeviceRow(
              name: known[i].name,
              idLabel: known[i].id,
              isUsb: false,
              online: ctrl.isKnownPresent(known[i]),
              active: ctrl.isKnownActive(known[i]),
              sessionConnected: ctrl.isKnownSessionConnected(known[i]),
              busy: _isBusy(ctrl, known[i]),
              onTap: () => _connectKnown(context, known[i]),
              onForget: () => ctrl.forgetKnown(known[i]),
              onDisconnect: () => ctrl.disconnectKnown(known[i]),
            ),
          ],
        ],
      ),
    );
  }

  static bool _isBusy(DeviceController ctrl, KnownDevice known) {
    if (ctrl.connectingKnownId == known.id) return true;
    final connecting = ctrl.client.connectingDevice;
    return connecting != null && known.matches(connecting);
  }

  static Future<void> _connectKnown(
    BuildContext context,
    KnownDevice known,
  ) async {
    final ctrl = DeviceScope.of(context);
    try {
      await ctrl.connectKnown(known);
    } catch (e) {
      if (!context.mounted) return;
      await showConnectionFailedDialog(context, e, isBle: true);
    }
  }

  static Future<void> _openPicker(BuildContext context) async {
    if (!context.mounted) return;
    final selected = await showConnectionDialog(context);
    if (selected == null || !context.mounted) return;

    final ctrl = DeviceScope.of(context);
    try {
      await ctrl.connect(selected);
    } catch (e) {
      if (!context.mounted) return;
      await showConnectionFailedDialog(context, e, isBle: selected.isBle);
    }
  }
}

class _ConnectActionRow extends StatelessWidget {
  const _ConnectActionRow({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Icon(Icons.search, size: 24, color: color),
            ),
            Expanded(
              child: Text(
                'Search',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.isUsb,
    required this.online,
    required this.active,
    required this.sessionConnected,
    required this.busy,
    required this.onTap,
    required this.onDisconnect,
    this.idLabel,
    this.onForget,
  });

  final String name;
  final String? idLabel;
  final bool isUsb;
  final bool online;
  final bool active;
  final bool sessionConnected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onForget;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final subtitle = busy
        ? 'Connecting…'
        : active
        ? 'Active'
        : sessionConnected
        ? 'Connected — tap to switch'
        : (idLabel ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy || active ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Icon(
                isUsb
                    ? Icons.usb
                    : active || sessionConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth,
                size: 24,
                color: active
                    ? colors.accent
                    : (online || sessionConnected)
                    ? colors.info
                    : colors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colors.accent,
                  ),
                )
              else if (active || sessionConnected)
                Tooltip(
                  message: 'Disconnect',
                  child: InkResponse(
                    onTap: onDisconnect,
                    radius: 18,
                    child: Icon(Icons.link_off, size: 18, color: colors.danger),
                  ),
                )
              else if (onForget != null)
                Tooltip(
                  message: 'Forget',
                  child: InkResponse(
                    onTap: onForget,
                    radius: 18,
                    child: Icon(Icons.close, size: 18, color: colors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

