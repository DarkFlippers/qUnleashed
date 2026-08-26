import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';

class AppActionEntry {
  const AppActionEntry({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.half = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  /// Placed side by side with the next entry instead of taking the full row.
  final bool half;
}

class AppActionSheet {
  static Future<void> show(
    BuildContext context, {
    required Widget icon,
    required String title,
    required String subtitle,
    required Widget details,
    required List<AppActionEntry> Function(BuildContext context) actions,
    Widget? trailing,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ActionDialog(
        icon: icon,
        title: title,
        subtitle: subtitle,
        details: details,
        actions: actions,
        trailing: trailing,
      ),
    );
  }
}

class _ActionDialog extends StatelessWidget {
  const _ActionDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.details,
    required this.actions,
    required this.trailing,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Widget details;
  final List<AppActionEntry> Function(BuildContext context) actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context).size;
    final entries = actions(context);

    return Dialog(
      backgroundColor: colors.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: media.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.dialogText,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
              details,
              const SizedBox(height: 16),
              ..._buildActions(context, entries),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    List<AppActionEntry> entries,
  ) {
    final out = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final next = i + 1 < entries.length ? entries[i + 1] : null;
      if (entry.half && next != null && next.half) {
        out.add(
          Row(
            children: [
              Expanded(child: _button(context, entry)),
              const SizedBox(width: 8),
              Expanded(child: _button(context, next)),
            ],
          ),
        );
        i++;
      } else {
        out.add(_button(context, entry));
      }
      if (i + 1 < entries.length) out.add(const SizedBox(height: 8));
    }
    return out;
  }

  Widget _button(BuildContext context, AppActionEntry entry) {
    return _ActionButton(
      label: entry.label,
      icon: entry.icon,
      color: entry.color,
      filled: entry.filled,
      onTap: () {
        Navigator.of(context).pop();
        entry.onTap();
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: child,
            ),
    );
  }
}
