import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class QIcon extends StatelessWidget {
  const QIcon({super.key, required this.asset, required this.color, this.size});

  final String asset;
  final Color color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class QIconBadge extends StatelessWidget {
  const QIconBadge({
    super.key,
    required this.asset,
    required this.color,
    this.size = 36,
    this.iconSize = 24,
    this.backgroundOpacity = 0.18,
    this.borderRadius = 8,
  });

  final String asset;
  final Color color;
  final double size;
  final double iconSize;
  final double backgroundOpacity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: QIcon(asset: asset, color: color, size: iconSize),
    );
  }
}
