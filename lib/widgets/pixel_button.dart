import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Replicates the pixel-art button from https://flipperunleashed.com/
//
// The site uses CSS border-image with corners.png / corners-green.png (40×40).
// Pixel analysis of those images reveals a 3-step staircase corner:
//
//   y 0-2  : cut = 13 px from each side  (large  — ≈ 65 % of 20 px border)
//   y 3-6  : cut =  7 px                 (medium — 35 %)
//   y 7-12 : cut =  3 px                 (small  — 15 %)
//   y 13+  : full width
//
// The path below encodes this exact staircase so the shape matches the site.
//
// Fonts used:
//   • regular nav buttons → Born2bSportyV2  (site .pxbtn / .pixel)
//   • large Install button → GravityBold8   (site .install p)
// ─────────────────────────────────────────────────────────────────────────────

class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.color,
    this.textColor = Colors.black,
    this.onTap,
    this.large = false,
    this.glowing = false,
    this.glowColor,
  });

  /// White nav-style button (matches site .pixel .pxbtn)
  const PixelButton.nav({
    super.key,
    required this.label,
    this.onTap,
  })  : color = Colors.white,
        textColor = Colors.black,
        large = false,
        glowing = false,
        glowColor = null;

  /// Large green Install button (matches site .install)
  const PixelButton.install({
    super.key,
    required this.label,
    this.onTap,
    this.glowing = true,
  })  : color = const Color(0xFF4ADC45),
        textColor = Colors.white,
        large = true,
        glowColor = const Color(0xFF4ADC45);

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;

  /// large=true → Install style (GravityBold8, bigger padding, 7px shadow)
  /// large=false → nav-button style (Born2bSportyV2, smaller, 4px shadow)
  final bool large;
  final bool glowing;
  final Color? glowColor;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.glowing) _glowCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PixelButton old) {
    super.didUpdateWidget(old);
    if (widget.glowing != old.glowing) {
      if (widget.glowing) {
        _glowCtrl.repeat(reverse: true);
      } else {
        _glowCtrl
          ..stop()
          ..reset();
      }
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shadow = widget.large ? 7.0 : 4.0;
    final corner = widget.large ? 20.0 : 10.0;
    final fontSize = widget.large ? 28.0 : 16.0;
    final hPad = widget.large ? 40.0 : 20.0;
    final vPad = widget.large ? 20.0 : 8.0;
    final fontFamily = widget.large ? 'GravityBold8' : 'Born2bSportyV2';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _glowCtrl,
        builder: (context, child) {
          final glowV = widget.glowing ? _glowCtrl.value : 0.0;
          final pressed = _pressed;
          return CustomPaint(
            painter: _PixelPainter(
              color: widget.color,
              shadow: shadow,
              corner: corner,
              pressed: pressed,
              glowValue: glowV,
              glowColor: widget.glowColor ?? widget.color,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                hPad + (pressed ? shadow : 0),
                vPad + (pressed ? shadow : 0),
                hPad + shadow - (pressed ? shadow : 0),
                vPad + shadow - (pressed ? shadow : 0),
              ),
              child: child,
            ),
          );
        },
        child: Text(
          widget.label,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            color: widget.textColor,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _PixelPainter extends CustomPainter {
  const _PixelPainter({
    required this.color,
    required this.shadow,
    required this.corner,
    required this.pressed,
    required this.glowValue,
    required this.glowColor,
  });

  final Color color;
  final double shadow;
  final double corner;
  final bool pressed;
  final double glowValue;
  final Color glowColor;

  /// Build the 3-step staircase-corner path.
  /// Proportions: 13/20 (large cut), 7/20 (medium), 3/20 (small).
  static Path _path(Rect r, double c) {
    final l = r.left, t = r.top, ri = r.right, b = r.bottom;
    final s = c * 13 / 20; // large  (65 %)
    final m = c * 7 / 20; //  medium (35 %)
    final n = c * 3 / 20; //  small  (15 %)
    return Path()
      // top edge
      ..moveTo(l + s, t)
      ..lineTo(ri - s, t)
      // ↘ top-right
      ..lineTo(ri - s, t + n)
      ..lineTo(ri - m, t + n)
      ..lineTo(ri - m, t + m)
      ..lineTo(ri - n, t + m)
      ..lineTo(ri - n, t + s)
      ..lineTo(ri, t + s)
      // right edge
      ..lineTo(ri, b - s)
      // ↙ bottom-right
      ..lineTo(ri - n, b - s)
      ..lineTo(ri - n, b - m)
      ..lineTo(ri - m, b - m)
      ..lineTo(ri - m, b - n)
      ..lineTo(ri - s, b - n)
      ..lineTo(ri - s, b)
      // bottom edge
      ..lineTo(l + s, b)
      // ↖ bottom-left
      ..lineTo(l + s, b - n)
      ..lineTo(l + m, b - n)
      ..lineTo(l + m, b - m)
      ..lineTo(l + n, b - m)
      ..lineTo(l + n, b - s)
      ..lineTo(l, b - s)
      // left edge
      ..lineTo(l, t + s)
      // ↗ top-left
      ..lineTo(l + n, t + s)
      ..lineTo(l + n, t + m)
      ..lineTo(l + m, t + m)
      ..lineTo(l + m, t + n)
      ..lineTo(l + s, t + n)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ox = pressed ? shadow : 0.0;
    final oy = pressed ? shadow : 0.0;
    final btnRect = Rect.fromLTWH(ox, oy, size.width - shadow, size.height - shadow);

    // Pulsing glow (for Install button)
    if (glowValue > 0) {
      final sigma = 6.0 + glowValue * 14.0;
      canvas.drawPath(
        _path(btnRect.inflate(sigma * 0.4), corner),
        Paint()
          ..color = glowColor.withValues(alpha: 0.2 + glowValue * 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      );
    }

    // Pixel-art drop shadow  (rgba(0,0,0,0.4), offset = shadow px)
    if (!pressed && shadow > 0) {
      canvas.drawPath(
        _path(
          Rect.fromLTWH(shadow, shadow, size.width - shadow, size.height - shadow),
          corner,
        ),
        Paint()..color = const Color(0x66000000),
      );
    }

    // Button fill
    canvas.drawPath(_path(btnRect, corner), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PixelPainter old) =>
      old.color != color ||
      old.pressed != pressed ||
      old.glowValue != glowValue ||
      old.shadow != shadow ||
      old.corner != corner;
}
