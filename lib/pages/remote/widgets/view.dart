import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/models.dart';

class RemoteControlView extends StatelessWidget {
  const RemoteControlView({
    super.key,
    required this.image,
    required this.queue,
    required this.orientation,
  });

  final ui.Image? image;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth =
            ((constraints.maxHeight - 74 - 85) * 2).clamp(0.0, constraints.maxWidth);

        return Center(
          child: SizedBox(
            width: screenWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: queue.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 4),
                      itemBuilder: (_, i) => _QueueIcon(
                        key: ValueKey(queue[i].id),
                        colors: colors,
                        asset: queue[i].asset,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.screenBorder, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.screenBorder, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: colors.screenBackground,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: _LiveFrame(
                      colors: colors,
                      image: image,
                      orientation: orientation,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SvgPicture.asset(
                  'assets/flipper_svg/screenstreaming/ic_flipper_logo.svg',
                  width: 183,
                  height: 22,
                  colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveFrame extends StatelessWidget {
  static const _w = 128;
  static const _h = 64;

  const _LiveFrame({required this.colors, required this.image, required this.orientation});

  final QAppColors colors;
  final ui.Image? image;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return SvgPicture.asset(
        'assets/flipper_svg/screenstreaming/pic_not_connected_light.svg',
        fit: BoxFit.fitWidth,
        colorFilter: ColorFilter.mode(colors.textMuted, BlendMode.srcIn),
      );
    }

    final isVertical =
        orientation == StreamOrientation.vertical || orientation == StreamOrientation.verticalFlip;

    return Center(
      child: AspectRatio(
        aspectRatio: isVertical ? (_h / _w).toDouble() : (_w / _h).toDouble(),
        child: RotatedBox(
          quarterTurns: isVertical ? 1 : 0,
          child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
        ),
      ),
    );
  }
}

class _QueueIcon extends StatefulWidget {
  const _QueueIcon({super.key, required this.colors, required this.asset});

  final QAppColors colors;
  final String asset;

  @override
  State<_QueueIcon> createState() => _QueueIconState();
}

class _QueueIconState extends State<_QueueIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();
  late final Animation<double> _scale = Tween<double>(begin: 0.86, end: 1).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: 24,
        height: 24,
        child: SvgPicture.asset(
          widget.asset,
          colorFilter: ColorFilter.mode(widget.colors.accent, BlendMode.srcIn),
        ),
      ),
    );
  }
}
