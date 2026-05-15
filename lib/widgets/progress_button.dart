import 'package:flutter/material.dart';

class ProgressButton extends StatefulWidget {
  const ProgressButton({
    super.key,
    required this.text,
    required this.color,
    this.onPressed,
    this.progress,
    this.indeterminate = false,
    this.showPercent = false,
    this.progressColor,
    this.height = defaultHeight,
    this.width,
    this.textStyle,
    this.borderRadius = defaultBorderRadius,
    this.horizontalPadding = defaultHorizontalPadding,
    this.verticalPadding = defaultVerticalPadding,
  });

  static const double defaultHeight = 50;
  static const double defaultBorderRadius = 9;
  static const double defaultHorizontalPadding = 8;
  static const double defaultVerticalPadding = 6;
  static const TextStyle defaultTextStyle = TextStyle(
    fontFamily: 'FlipperBold',
    fontSize: 40,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: Colors.white,
  );

  static const double _borderWidth = 1.25;
  static const double _solidBgOpacity = 1;
  static const double _trackOpacity = 0.38;
  static const double _indeterminateBarFraction = 0.35;
  static const Duration _indeterminateCycle = Duration(milliseconds: 1400);

  final String text;
  final Color color;
  final VoidCallback? onPressed;
  final double? progress;
  final bool indeterminate;
  final bool showPercent;
  final Color? progressColor;
  final double height;
  final double? width;
  final TextStyle? textStyle;
  final double borderRadius;
  final double horizontalPadding;
  final double verticalPadding;

  bool get _hasFill => progress != null || indeterminate;

  @override
  State<ProgressButton> createState() => _ProgressButtonState();
}

class _ProgressButtonState extends State<ProgressButton>
    with SingleTickerProviderStateMixin {
  AnimationController? _indeterminateController;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ProgressButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indeterminate != widget.indeterminate) _syncController();
  }

  void _syncController() {
    if (widget.indeterminate) {
      _indeterminateController ??= AnimationController(
        vsync: this,
        duration: ProgressButton._indeterminateCycle,
      )..repeat();
    } else {
      _indeterminateController?.dispose();
      _indeterminateController = null;
    }
  }

  @override
  void dispose() {
    _indeterminateController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final hasFill = widget._hasFill;
    final clamped = (widget.progress ?? 0).clamp(0.0, 1.0);
    final bgOpacity = hasFill
        ? ProgressButton._trackOpacity
        : ProgressButton._solidBgOpacity;
    final fillColor = widget.progressColor ?? widget.color;
    final label = widget.showPercent && widget.progress != null
        ? '${widget.text} ${(clamped * 100).round()}%'
        : widget.text;

    final Widget fill;
    if (!hasFill) {
      fill = const SizedBox.shrink();
    } else if (widget.indeterminate) {
      fill = _IndeterminateBar(
        controller: _indeterminateController!,
        color: fillColor,
        radius: radius,
        barFraction: ProgressButton._indeterminateBarFraction,
      );
    } else {
      fill = Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: fillColor, borderRadius: radius),
          ),
        ),
      );
    }

    final body = ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: widget.height,
        width: widget.width ?? double.infinity,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: bgOpacity),
            borderRadius: radius,
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: widget.color,
              width: ProgressButton._borderWidth,
            ),
            borderRadius: radius,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: fill),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.horizontalPadding,
                    vertical: widget.verticalPadding,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false,
                        applyHeightToLastDescent: false,
                      ),
                      style: (widget.textStyle ?? ProgressButton.defaultTextStyle)
                          .copyWith(
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.text,
      value: widget.progress != null ? '${(clamped * 100).round()}%' : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: body,
      ),
    );
  }
}

class _IndeterminateBar extends StatelessWidget {
  const _IndeterminateBar({
    required this.controller,
    required this.color,
    required this.radius,
    required this.barFraction,
  });

  final AnimationController controller;
  final Color color;
  final BorderRadius radius;
  final double barFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barWidth = width * barFraction;
        final travel = width + barWidth;
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final left = -barWidth + travel * controller.value;
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: barWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: color, borderRadius: radius),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
