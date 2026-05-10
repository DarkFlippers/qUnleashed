import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../controller.dart';
import '../models/category.dart';
import 'category_tile.dart';

class CategoriesCard extends StatelessWidget {
  const CategoriesCard({
    super.key,
    required this.controller,
    required this.onOpenCategory,
    required this.onOpenDeleted,
  });

  final ArchiveController controller;
  final ValueChanged<ArchiveCategory> onOpenCategory;
  final VoidCallback onOpenDeleted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tiles = <Widget>[];
    for (var i = 0; i < ArchiveCategory.values.length; i++) {
      final cat = ArchiveCategory.values[i];
      tiles.add(CategoryTile.forCategory(
        category: cat,
        count: controller.countFor(cat),
        onTap: () => onOpenCategory(cat),
      ));
      tiles.add(Divider(height: 1, color: colors.divider));
    }
    tiles.add(CategoryTile.deleted(
      count: controller.deletedCount,
      onTap: onOpenDeleted,
    ));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(children: tiles),
      ),
    );
  }
}
