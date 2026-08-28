import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../../data/models/category.dart';
import '../../../../components/remote_image.dart';

Color parseHexColor(String hex, {Color fallback = const Color(0xFFEBEBEB)}) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return fallback;
  return Color(v);
}

/// The category's own icon — a bundled asset when there is one, the catalog's
/// SVG otherwise, nothing at all when the category has neither.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.category,
    required this.color,
    required this.size,
    required this.gap,
  });

  final AppCategory category;
  final Color color;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final asset = category.iconAsset;
    final uri = category.iconUri;
    final Widget icon;
    if (asset != null) {
      icon = QIcon(asset: asset, color: color, size: size);
    } else if (uri != null && uri.isNotEmpty) {
      icon = SafeNetworkSvg(
        url: uri,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(right: gap),
      child: icon,
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.category,
    required this.selected,
    this.onTap,
  });

  final AppCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = parseHexColor(category.color);
    final bg = selected
        ? base
        : Color.alphaBlend(base.withAlpha(70), colors.card);
    const textColor = Colors.black;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategoryIcon(
                category: category,
                color: textColor,
                size: 14,
                gap: 6,
              ),
              Text(
                category.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
