import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/models/app_entry.dart';

/// Which of an item's entries the page shows and installs: its external apps
/// (ProtoPirate, ProtoPirate Extra) from each catalogue that carries it.
class CatalogAppPicker extends StatelessWidget {
  const CatalogAppPicker({
    super.key,
    required this.entries,
    required this.selected,
    required this.onChanged,
    required this.isInstalled,
  });

  final List<CatalogApp> entries;
  final CatalogApp selected;
  final ValueChanged<CatalogApp> onChanged;
  final bool Function(CatalogApp entry) isInstalled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          child: PopupMenuButton<CatalogApp>(
            initialValue: selected,
            onSelected: onChanged,
            position: PopupMenuPosition.under,
            color: colors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) => [
              for (final entry in entries)
                PopupMenuItem<CatalogApp>(
                  value: entry,
                  child: _Line(
                    entry: entry,
                    bold: entry.id == selected.id,
                    installed: isInstalled(entry),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '${context.l10n.appMetaVariant}: ',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  Expanded(
                    child: _Line(
                      entry: selected,
                      bold: true,
                      installed: isInstalled(selected),
                    ),
                  ),
                  Icon(Icons.expand_more, color: colors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.entry,
    required this.bold,
    required this.installed,
  });

  final CatalogApp entry;
  final bool bold;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            entry.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        if (installed) ...[
          const SizedBox(width: 6),
          Icon(Icons.check_circle, size: 16, color: colors.accent),
        ],
      ],
    );
  }
}
