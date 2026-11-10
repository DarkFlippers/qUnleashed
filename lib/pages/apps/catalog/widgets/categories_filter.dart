import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../data/models/category.dart';
import 'category_chip.dart';

/// Top-level categories, and the folders of one of them once it is picked.
///
/// Every folder on one screen was too much for a phone - Sub-GHz, NFC and the
/// rest each bring their own, and the chips wrapped into a wall above the
/// first card. A folder only narrows what its category already shows (the
/// server's filter on a category includes its folders), so nothing is lost
/// by keeping them out of sight until the category is chosen.
class CategoriesFilter extends StatelessWidget {
  const CategoriesFilter({
    super.key,
    required this.categories,
    required this.current,
    required this.onSelect,
    this.allLabel,
  });

  /// Flat, as `nestCategories` orders it: each category before its folders.
  final List<AppCategory> categories;
  final AppCategory? current;
  final ValueChanged<AppCategory?> onSelect;
  final String? allLabel;

  static AppCategory _allCategory(String name) =>
      AppCategory(id: '-1', name: name, color: 'EBEBEB');

  @override
  Widget build(BuildContext context) {
    final ids = {for (final c in categories) c.id};
    // A folder whose parent the server did not send has nowhere to hide.
    bool isRoot(AppCategory c) =>
        c.parentId == null || !ids.contains(c.parentId);
    final current = this.current;
    final openRoot = current == null
        ? null
        : isRoot(current)
        ? current.id
        : current.parentId;
    final folders = [
      for (final c in categories)
        if (!isRoot(c) && c.parentId == openRoot) c,
    ];

    // "All apps" includes every category in the search, so all category chips
    // read as active in that mode instead of being dimmed. A category works
    // the same way for its folders, and stays lit while one of them is
    // picked.
    final allSelected = current == null;
    final rootSelected = current != null && current.id == openRoot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CategoryChip(
              category: _allCategory(allLabel ?? context.l10n.appsAllApps),
              selected: allSelected,
              onTap: () => onSelect(null),
            ),
            for (final cat in categories)
              if (isRoot(cat))
                CategoryChip(
                  category: cat,
                  selected: allSelected || cat.id == openRoot,
                  onTap: () => onSelect(cat),
                ),
          ],
        ),
        if (folders.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final folder in folders)
                CategoryChip(
                  category: folder,
                  selected: rootSelected || folder.id == current?.id,
                  onTap: () => onSelect(folder),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
