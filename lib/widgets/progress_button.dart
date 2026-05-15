import 'package:flutter/material.dart';

class ProgressButton extends StatelessWidget {
  const ProgressButton({
    super.key,
    required this.text,
    required this.color,
    this.onPressed,
    this.progress = double.nan,
    this.showPercent = false,
    this.progressColor,
  });

  static const double _height = 50;
  static const double _borderRadius = 9;
  static const double _borderWidth = 1.25;
  static const double _buttonOpacity = 1;
  static const double _progressOpacity = 0.38;
  static const double _horizontalPadding = 8;
  static const double _verticalPadding = 6;
  static const TextStyle _textStyle = TextStyle(
    fontFamily: 'FlipperBold',
    fontSize: 40,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: Colors.white,
  );

  final String text;
  final Color color;
  final VoidCallback? onPressed;
  final double progress;
  final bool showPercent;
  final Color? progressColor;

  bool get _isButtonMode => progress.isNaN;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_borderRadius);
    final progressValue = _isButtonMode ? 1.0 : progress.clamp(0.0, 1.0);
    final backgroundOpacity = _isButtonMode ? _buttonOpacity : _progressOpacity;
    final label = showPercent && !_isButtonMode
        ? '$text ${(progressValue * 100).round()}%'
        : text;

    return GestureDetector(
      onTap: _isButtonMode ? onPressed : null,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: _height,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: backgroundOpacity),
                    border: Border.all(color: color, width: _borderWidth),
                    borderRadius: radius,
                  ),
                ),
              ),
              if (!_isButtonMode)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: constraints.maxWidth * progressValue,
                          height: constraints.maxHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: progressColor ?? color,
                              borderRadius: radius,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: _borderWidth),
                    borderRadius: radius,
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _horizontalPadding,
                    vertical: _verticalPadding,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: _textStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
