import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class FlipperActionRow extends StatelessWidget {
  const FlipperActionRow({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  final String iconAsset;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: SvgPicture.asset(iconAsset, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
          ),
        ),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ?trailing,
      ],
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: row,
      ),
    );
  }
}
