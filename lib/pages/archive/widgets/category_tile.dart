import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/category.dart';

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.title,
    required this.asset,
    required this.color,
    required this.count,
    required this.onTap,
  });

  final String title;
  final String asset;
  final Color color;
  final int count;
  final VoidCallback onTap;

  factory CategoryTile.forCategory({
    required ArchiveCategory category,
    required int count,
    required VoidCallback onTap,
  }) {
    return CategoryTile(
      title: category.title,
      asset: category.asset,
      color: category.color,
      count: count,
      onTap: onTap,
    );
  }

  factory CategoryTile.deleted({
    required int count,
    required VoidCallback onTap,
  }) {
    return CategoryTile(
      title: 'Deleted',
      asset: 'assets/flipper_svg/archive/ic_trash.svg',
      color: const Color(0xFF8D8D8D),
      count: count,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SvgPicture.asset(
                asset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(color: colors.textMuted, fontSize: 14),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
