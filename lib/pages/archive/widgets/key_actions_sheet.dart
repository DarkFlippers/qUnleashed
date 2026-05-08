import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../archive_controller.dart';
import '../models/archive_key.dart';

class KeyActionsSheet extends StatelessWidget {
  const KeyActionsSheet({
    super.key,
    required this.controller,
    required this.flipperKey,
  });

  final ArchiveController controller;
  final ArchiveKey flipperKey;

  static Future<void> show(BuildContext context, ArchiveController controller, ArchiveKey key) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).extension<QAppColors>()!.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => KeyActionsSheet(controller: controller, flipperKey: key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final k = flipperKey;
    final connected = controller.isConnected;

    final actions = <_Action>[];
    if (k.state == ArchiveKeyState.remoteOnly && connected) {
      actions.add(_Action(
        icon: Icons.download,
        label: 'Save to phone',
        onTap: () => controller.rememberKey(k),
      ));
    }
    if (k.state == ArchiveKeyState.synced || k.state == ArchiveKeyState.remoteOnly) {
      actions.add(_Action(
        icon: Icons.delete_outline,
        label: connected ? 'Delete from device' : 'Move to deleted',
        destructive: true,
        onTap: () => controller.deleteKey(k),
      ));
    }
    if (k.state == ArchiveKeyState.localOnly) {
      actions.add(_Action(
        icon: Icons.delete_outline,
        label: 'Move to deleted',
        destructive: true,
        onTap: () => controller.deleteKey(k),
      ));
    }
    if (k.state == ArchiveKeyState.deleted) {
      actions.add(_Action(
        icon: Icons.restore,
        label: connected ? 'Restore to device' : 'Restore locally',
        onTap: () => controller.restoreKey(k),
      ));
      actions.add(_Action(
        icon: Icons.delete_forever,
        label: 'Delete permanently',
        destructive: true,
        onTap: () => controller.purgeKey(k),
      ));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: k.category.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SvgPicture.asset(
                    k.category.asset,
                    width: 22,
                    height: 22,
                    colorFilter:
                        ColorFilter.mode(k.category.color, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        k.remotePath,
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.divider),
          for (final a in actions)
            ListTile(
              leading: Icon(
                a.icon,
                color: a.destructive ? colors.danger : colors.textPrimary,
              ),
              title: Text(
                a.label,
                style: TextStyle(
                  color: a.destructive ? colors.danger : colors.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                a.onTap();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Action {
  _Action({required this.icon, required this.label, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}
