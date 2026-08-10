import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class SyncProgressBar extends StatelessWidget {
  const SyncProgressBar({
    super.key,
    required this.icon,
    required this.label,
    required this.progress,
    required this.color,
    this.fileProgress,
  });

  final IconData icon;
  final String label;
  final double progress;
  final double? fileProgress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          minHeight: 3,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ),
              if (progress > 0 || fileProgress != null)
                Text(
                  fileProgress == null
                      ? '${(progress * 100).round()}%'
                      : '${(progress * 100).round()}% / '
                            '${(fileProgress! * 100).round()}%',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
