import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'flipper_image.dart';

class ScreenshotFrame extends StatelessWidget {
  const ScreenshotFrame({
    super.key,
    required this.url,
    this.aspectRatio = 256 / 128,
    this.borderColor = Colors.black,
    this.borderWidth = 2,
    this.innerPadding = 4,
    this.borderRadius = 6,
  });

  final String url;
  final double aspectRatio;
  final Color borderColor;
  final double borderWidth;
  final double innerPadding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bg = colors.isDark ? colors.screenBackground : colors.accent;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        padding: EdgeInsets.all(innerPadding),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius - 2),
          child: FlipperRemoteImage(url: url, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
