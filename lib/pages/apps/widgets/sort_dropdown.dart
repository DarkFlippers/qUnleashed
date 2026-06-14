import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../catalog_api.dart';

class SortDropdown extends StatelessWidget {
  const SortDropdown({super.key, required this.value, required this.onChanged});

  final AppsSort value;
  final ValueChanged<AppsSort> onChanged;

  static const Map<AppsSort, String> _labels = {
    AppsSort.newUpdates: 'New Updates',
    AppsSort.newReleases: 'New Releases',
    AppsSort.oldUpdates: 'Old Updates',
    AppsSort.oldReleases: 'Old Releases',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(22),
      child: PopupMenuButton<AppsSort>(
        initialValue: value,
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        color: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (context) => [
          for (final entry in _labels.entries)
            PopupMenuItem<AppsSort>(
              value: entry.key,
              child: Text(
                entry.value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: entry.key == value ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _labels[value]!,
                style: TextStyle(
                  color: colors.onAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_drop_down, color: colors.onAccent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
