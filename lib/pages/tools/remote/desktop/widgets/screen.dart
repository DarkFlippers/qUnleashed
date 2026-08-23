import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../components/flipper_screen_animation.dart';

import '../../../../../theme/colors/display.dart';
import '../../../../../theme/theme.dart';
import '../layout.dart';
import '../models/models.dart';

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({
    super.key,
    required this.size,
    this.queueAtBottom = false,
    required this.frameListenable,
    required this.queue,
    required this.orientation,
  });

  final Size size;
  final bool queueAtBottom;
  final ValueListenable<ui.Image?> frameListenable;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final frameWidth = size.width - RemoteScreenGeometry.bezel;
    final frameHeight = RemoteScreenGeometry.frameHeight(size.height);

    final strip = SizedBox(
      width: frameWidth,
      height: RemoteScreenGeometry.queueHeight,
      child: queue.isEmpty
          ? null
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: queue.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) => _QueueIcon(
                key: ValueKey(queue[i].id),
                colors: colors,
                asset: queue[i].asset,
              ),
            ),
    );

    final shell = _Shell(
      colors: colors,
      frameListenable: frameListenable,
      orientation: orientation,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );

    return SizedBox.fromSize(
      size: size,
      child: Column(
        children: queueAtBottom
            ? [
                shell,
                const SizedBox(height: RemoteScreenGeometry.queueSpacing),
                strip,
              ]
            : [
                strip,
                const SizedBox(height: RemoteScreenGeometry.queueSpacing),
                shell,
              ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.colors,
    required this.frameListenable,
    required this.orientation,
    required this.frameWidth,
    required this.frameHeight,
  });

  final QAppColors colors;
  final ValueListenable<ui.Image?> frameListenable;
  final StreamOrientation orientation;
  final double frameWidth;
  final double frameHeight;

  @override
  Widget build(BuildContext context) {
    final display = DisplayColors.forColors(colors);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: display.border, width: 3),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: display.border, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: display.background,
        ),
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: frameWidth,
          height: frameHeight,
          child: RepaintBoundary(
            child: ValueListenableBuilder<ui.Image?>(
              valueListenable: frameListenable,
              builder: (_, image, _) =>
                  _LiveFrame(image: image, orientation: orientation),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveFrame extends StatelessWidget {
  const _LiveFrame({required this.image, required this.orientation});

  final ui.Image? image;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      final display = DisplayColors.forColors(context.appColors);
      return FlipperScreenAnimation(
        active: true,
        fg: display.foreground,
        bg: display.background,
      );
    }

    final isVertical =
        orientation == StreamOrientation.vertical ||
        orientation == StreamOrientation.verticalFlip;

    return RotatedBox(
      quarterTurns: isVertical ? 1 : 0,
      child: RawImage(
        image: image,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none,
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

class _QueueIconState extends State<_QueueIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();
  late final Animation<double> _scale = Tween<double>(
    begin: 0.86,
    end: 1,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

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
