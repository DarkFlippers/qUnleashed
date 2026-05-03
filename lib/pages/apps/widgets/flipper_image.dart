import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';

class FlipperRemoteImage extends StatelessWidget {
  const FlipperRemoteImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.pixelated = true,
    this.placeholderAsset = 'assets/apps/app_placeholder.svg',
    this.placeholderColor,
  });

  final String url;
  final BoxFit fit;
  final bool pixelated;
  final String placeholderAsset;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = placeholderColor ?? colors.textMuted;

    if (url.isEmpty) {
      return _placeholder(tint);
    }

    final isSvg = url.toLowerCase().endsWith('.svg');
    if (isSvg) {
      return SvgPicture.network(
        url,
        fit: fit,
        placeholderBuilder: (_) => _placeholder(tint),
      );
    }

    return Image.network(
      url,
      fit: fit,
      filterQuality: pixelated ? FilterQuality.none : FilterQuality.medium,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(tint);
      },
      errorBuilder: (_, _, _) => _placeholder(tint),
    );
  }

  Widget _placeholder(Color tint) {
    return Center(
      child: SvgPicture.asset(
        placeholderAsset,
        colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        width: 28,
        height: 28,
      ),
    );
  }
}
