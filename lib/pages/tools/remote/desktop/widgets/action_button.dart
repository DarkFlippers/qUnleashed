import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../theme.dart';

class RemoteControlActionButton extends StatelessWidget {
  static const double width = 86;

  const RemoteControlActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.asset,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.screenOptionBackground,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: asset != null
                  ? SvgPicture.asset(
                      asset!,
                      colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
                    )
                  : Icon(icon, color: colors.accent, size: 24),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.accent),
          ),
        ],
      ),
    );
  }
}
