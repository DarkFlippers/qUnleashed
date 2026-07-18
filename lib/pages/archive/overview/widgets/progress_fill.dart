import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';

class ProgressFill extends StatelessWidget {
  const ProgressFill({super.key, required this.progress, this.alpha = 0.14});

  final double? progress;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) return const SizedBox.shrink();
    final colors = context.appColors;
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: p.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (_, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            heightFactor: 1,
            child: ColoredBox(color: colors.accent.withValues(alpha: alpha)),
          ),
        ),
      ),
    );
  }
}
