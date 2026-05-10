import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';

class FlipperMockupWidget extends StatelessWidget {
  const FlipperMockupWidget({
    super.key,
    required this.active,
  });

  static const _templateWidth = 238.0;
  static const _templateHeight = 100.0;
  static const _screenLeft = 60.65;
  static const _screenTop = 10.54;
  static const _screenWidth = 85.32;
  static const _screenHeight = 46.95;

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AspectRatio(
      aspectRatio: _templateWidth / _templateHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.asset(
                colors.isDark
                    ? (active
                        ? 'assets/flipper_svg/mockup/template_black_flipper_active.svg'
                        : 'assets/flipper_svg/mockup/template_black_flipper_disabled.svg')
                    : (active
                        ? 'assets/flipper_svg/mockup/template_white_flipper_active.svg'
                        : 'assets/flipper_svg/mockup/template_white_flipper_disabled.svg'),
              ),
              Positioned(
                left: w * (_screenLeft / _templateWidth),
                top: h * (_screenTop / _templateHeight),
                width: w * (_screenWidth / _templateWidth),
                height: h * (_screenHeight / _templateHeight),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * (3.4 / 238)),
                  child: RepaintBoundary(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: w,
                      maxWidth: w,
                      minHeight: h,
                      maxHeight: h,
                      child: Transform.translate(
                        offset: Offset(
                          -w * (_screenLeft / _templateWidth),
                          -h * (_screenTop / _templateHeight),
                        ),
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: const _MockupInnerScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MockupInnerScreen extends StatelessWidget {
  const _MockupInnerScreen();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/flipper_svg/mockup/pic_flipperscreen_default.svg',
      fit: BoxFit.fill,
    );
  }
}
