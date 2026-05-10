import 'package:flutter/material.dart';

import '../models/category.dart';
import 'category_chip.dart';

class CategoriesFilter extends StatelessWidget {
  const CategoriesFilter({
    super.key,
    required this.categories,
    required this.current,
    required this.onSelect,
    this.allLabel = 'All apps',
  });

  final List<AppCategory> categories;
  final AppCategory? current;
  final ValueChanged<AppCategory?> onSelect;
  final String allLabel;

  static const _allCategory = AppCategory(
    id: '-1',
    name: 'All apps',
    color: 'EBEBEB',
  );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        CategoryChip(
          category: _allCategory,
          selected: current == null,
          onTap: () => onSelect(null),
        ),
        for (final cat in categories)
          CategoryChip(
            category: cat,
            selected: current?.id == cat.id,
            onTap: () => onSelect(cat),
          ),
      ],
    );
  }
}
