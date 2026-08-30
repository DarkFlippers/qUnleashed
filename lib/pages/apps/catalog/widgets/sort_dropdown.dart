import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_api.dart';

class SortDropdown extends StatelessWidget {
  const SortDropdown({super.key, required this.value, required this.onChanged});

  final AppsSort value;
  final ValueChanged<AppsSort> onChanged;

  static String _label(L10n s, AppsSort sort) => switch (sort) {
    AppsSort.newUpdates => s.sortNewUpdates,
    AppsSort.newReleases => s.sortNewReleases,
    AppsSort.oldUpdates => s.sortOldUpdates,
    AppsSort.oldReleases => s.sortOldReleases,
    AppsSort.alphabetical => s.sortAlphabetical,
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
          for (final sort in AppsSort.values)
            PopupMenuItem<AppsSort>(
              value: sort,
              child: Text(
                _label(context.l10n, sort),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: sort == value ? FontWeight.w700 : FontWeight.w500,
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
                _label(context.l10n, value),
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
