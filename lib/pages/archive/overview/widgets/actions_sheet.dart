import 'package:flutter/material.dart';

import '../../../../theme.dart';

/// A single action shown as a square tile in [ActionsSheet].
class ActionItem {
  ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// Shared file-actions dialog used by both the archive (category/key) pages and
/// the file manager, so the look and interaction of the "actions" grid stays
/// identical everywhere. Callers build the [actions] list for their own
/// backend; this widget only renders the header and the tile grid.
class ActionsSheet {
  const ActionsSheet._();

  static Future<void> show(
    BuildContext context, {
    required Widget leading,
    required String title,
    required String subtitle,
    required List<ActionItem> actions,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _ActionsSheetBody(
              leading: leading,
              title: title,
              subtitle: subtitle,
              actions: actions,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsSheetBody extends StatelessWidget {
  const _ActionsSheetBody({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final List<ActionItem> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            ActionsGrid(actions: actions),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class ActionsGrid extends StatelessWidget {
  const ActionsGrid({super.key, required this.actions});

  final List<ActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in actions)
            SizedBox(width: 72, height: 72, child: _ActionTile(action: a)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final ActionItem action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = action.destructive ? colors.danger : colors.textSecondary;

    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          action.onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
