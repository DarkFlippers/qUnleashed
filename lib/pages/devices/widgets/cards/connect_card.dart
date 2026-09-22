import 'package:flutter/material.dart';

import '../../../../components/dialogs/connection.dart';
import '../../../../services/connection/link_service.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../page_card.dart';

class ConnectCard extends StatelessWidget {
  const ConnectCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final links = LinkService.instance;

    return ListenableBuilder(
      listenable: links,
      builder: (context, _) {
        final entries = links.entries;
        return FlipperPageCard(
          child: Column(
            children: [
              _ConnectActionRow(
                color: colors.accent,
                onTap: () => promptConnectDevice(context),
              ),
              for (final entry in entries) ...[
                Divider(height: 1, color: colors.divider),
                _DeviceRow(
                  entry: entry,
                  onTap: () => connectLinkEntry(context, entry),
                  onDisconnect: () => links.disconnect(entry),
                  onForget: entry.isBle && !entry.held
                      ? () => links.forget(entry)
                      : null,
                ),
              ],
            ],
          ),
        );
      },
    );
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
                context.l10n.connectSearch,
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
    required this.entry,
    required this.onTap,
    required this.onDisconnect,
    this.onForget,
  });

  final LinkEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;
  final VoidCallback? onForget;

  String _subtitle(BuildContext context) {
    final strings = context.l10n;
    if (entry.busy) return strings.pickerConnecting;
    switch (entry.session) {
      case LinkSession.active:
        return strings.connectActive;
      case LinkSession.connected:
        return strings.connectTapToSwitch;
      case LinkSession.connecting:
        return strings.pickerConnecting;
      case LinkSession.none:
        return entry.address;
    }
  }

  Color _iconColor(QAppColors colors) {
    if (entry.session == LinkSession.active) return colors.accent;
    if (entry.held) return colors.info;
    return entry.isBle && entry.heard ? colors.info : colors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = entry.session == LinkSession.active;
    final busy = entry.busy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy || active ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Icon(
                entry.isUsb
                    ? (entry.held ? Icons.cable : Icons.usb)
                    : entry.held
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth,
                size: 24,
                color: _iconColor(colors),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
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
                      _subtitle(context),
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
              else if (entry.held)
                Tooltip(
                  message: context.l10n.pickerDisconnect,
                  child: InkResponse(
                    onTap: onDisconnect,
                    radius: 18,
                    child: Icon(Icons.link_off, size: 18, color: colors.danger),
                  ),
                )
              else if (onForget != null)
                Tooltip(
                  message: context.l10n.connectForget,
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
