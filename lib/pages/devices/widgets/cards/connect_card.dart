import 'package:flutter/material.dart';

import '../../../../components/dialogs/connection.dart';
import '../../../../components/dialogs/connection_error.dart';
import '../../../../theme/theme.dart';
import '../../../../widgets/page_card.dart';
import '../../device_scope.dart';

class ConnectCard extends StatelessWidget {
  const ConnectCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FlipperPageCard(
      child: _ConnectActionRow(
        color: context.appColors.accent,
        onTap: () => _openPicker(context),
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: SizedBox(
                width: 44,
                height: 24,
                child: Row(
                  children: [
                    Icon(Icons.usb, size: 22, color: color),
                    const SizedBox(width: 2),
                    Icon(Icons.bluetooth, size: 20, color: color),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Connect',
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
