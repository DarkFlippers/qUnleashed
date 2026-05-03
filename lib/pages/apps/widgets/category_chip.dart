import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/app_category.dart';

Color parseHexColor(String hex, {Color fallback = const Color(0xFFEBEBEB)}) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return fallback;
  return Color(v);
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
    final bg = selected ? base : Color.alphaBlend(base.withAlpha(70), colors.card);
    final luminance = base.computeLuminance();
    final fg = luminance > 0.6 ? Colors.black : Colors.white;
    final textColor = selected ? fg : colors.textPrimary;

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
              if (category.iconUri != null && category.iconUri!.isNotEmpty) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: SvgPicture.network(
                    category.iconUri!,
                    colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 6),
              ],
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
