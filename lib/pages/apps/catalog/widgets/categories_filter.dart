import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../data/models/category.dart';
import 'category_chip.dart';

class CategoriesFilter extends StatelessWidget {
  const CategoriesFilter({
    super.key,
    required this.categories,
    required this.current,
    required this.onSelect,
    this.allLabel,
  });

  final List<AppCategory> categories;
  final AppCategory? current;
  final ValueChanged<AppCategory?> onSelect;
  final String? allLabel;

  static AppCategory _allCategory(String name) =>
      AppCategory(id: '-1', name: name, color: 'EBEBEB');

  @override
  Widget build(BuildContext context) {
    // "All apps" includes every category in the search, so all category chips
    // read as active in that mode instead of being dimmed.
    final allSelected = current == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        CategoryChip(
          category: _allCategory(allLabel ?? context.l10n.appsAllApps),
          selected: allSelected,
          onTap: () => onSelect(null),
        ),
        for (final cat in categories)
          CategoryChip(
            category: cat,
            selected: allSelected || current?.id == cat.id,
            onTap: () => onSelect(cat),
          ),
      ],
    );
  }
}
