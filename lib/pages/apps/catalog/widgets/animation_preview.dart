import 'package:flutter/material.dart';

import '../../../../components/flipper_screen_animation.dart';
import '../../../../theme/theme.dart';
import '../../data/animation_files.dart';

class AnimationPreview extends StatelessWidget {
  const AnimationPreview({
    super.key,
    required this.files,
    required this.versionId,
    this.still = false,
  });

  final AnimationFiles files;
  final String versionId;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bg = colors.isDark ? colors.screenBackground : colors.accent;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(4),
      child: AspectRatio(
        aspectRatio: 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: FlipperScreenAnimation(
            key: ValueKey('$versionId/$still'),
            active: versionId.isNotEmpty,
            fg: Colors.black,
            bg: bg,
            still: still,
            source: (name, wanted) =>
                files.read(versionId, name, wanted: wanted),
          ),
        ),
      ),
    );
  }
}
