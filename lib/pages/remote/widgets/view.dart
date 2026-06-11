import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/models.dart';

class RemoteControlView extends StatelessWidget {
  static const double _queueHeight = 28;
  static const double _queueSpacing = 4;
  static const double _logoSpacing = 12;
  static const double _logoHeight = 22;
  static const double _logoWidth = 183;
  static const double _frameChrome = 28;

  const RemoteControlView({
    super.key,
    required this.frameListenable,
    required this.queue,
    required this.orientation,
  });

  final ValueListenable<ui.Image?> frameListenable;
  final List<QueuedButton> queue;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isVertical =
        orientation == StreamOrientation.vertical ||
        orientation == StreamOrientation.verticalFlip;
    final frameAspectRatio = isVertical ? 0.5 : 2.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameMaxWidth = (constraints.maxWidth - _frameChrome).clamp(
          0.0,
          double.infinity,
        );
        final fixedHeight =
            _queueHeight + _queueSpacing + _logoSpacing + _logoHeight;
        final frameMaxHeight =
            (constraints.maxHeight - fixedHeight - _frameChrome).clamp(
              0.0,
              double.infinity,
            );
        final frameWidth = (frameMaxHeight * frameAspectRatio).clamp(
          0.0,
          frameMaxWidth,
        );
        final shellWidth = frameWidth + _frameChrome;

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: shellWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: frameWidth,
                    height: _queueHeight,
                    child: queue.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: queue.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 4),
                            itemBuilder: (_, i) => _QueueIcon(
                              key: ValueKey(queue[i].id),
                              colors: colors,
                              asset: queue[i].asset,
                            ),
                          ),
                  ),
                  const SizedBox(height: _queueSpacing),
                  _ScreenShell(
                    colors: colors,
                    frameListenable: frameListenable,
                    orientation: orientation,
                    frameWidth: frameWidth,
                  ),
                  const SizedBox(height: _logoSpacing),
                  SizedBox(
                    height: _logoHeight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SvgPicture.asset(
                        'assets/ic/device/logo.svg',
                        width: _logoWidth,
                        height: _logoHeight,
                        colorFilter: ColorFilter.mode(
                          colors.accent,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScreenShell extends StatelessWidget {
  const _ScreenShell({
    required this.colors,
    required this.frameListenable,
    required this.orientation,
    required this.frameWidth,
  });

  final QAppColors colors;
  final ValueListenable<ui.Image?> frameListenable;
  final StreamOrientation orientation;
  final double frameWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        child: SizedBox(
          width: frameWidth,
          child: RepaintBoundary(
            child: ValueListenableBuilder<ui.Image?>(
              valueListenable: frameListenable,
              builder: (_, image, _) => _LiveFrame(
                colors: colors,
                image: image,
                orientation: orientation,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveFrame extends StatelessWidget {
  static const _w = 128;
  static const _h = 64;

  const _LiveFrame({
    required this.colors,
    required this.image,
    required this.orientation,
  });

  final QAppColors colors;
  final ui.Image? image;
  final StreamOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return SvgPicture.asset(
        'assets/pic/status/disconnected.svg',
        fit: BoxFit.fitWidth,
      );
    }

    final isVertical =
        orientation == StreamOrientation.vertical ||
        orientation == StreamOrientation.verticalFlip;

    return Center(
      child: AspectRatio(
        aspectRatio: isVertical ? (_h / _w).toDouble() : (_w / _h).toDouble(),
        child: RotatedBox(
          quarterTurns: isVertical ? 1 : 0,
          child: RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
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
