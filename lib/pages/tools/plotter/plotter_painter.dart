import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'analysis/autorange.dart';
import 'analysis/slicer.dart';

const double kPlotHeight = 300;
const double _marginTop = 50;
const double _marginBottom = 50;
const double _breakpointZoom = 10;
const double _breakpointPulseInOneX = 75;

const double _hiLine = 4;
const double _loLine = 4;
const double _edgeLine = 1;
const double _hintLine = 1;
const double _hintAltLine = 3;
const double _fontSize = 10;

@immutable
class PlotterPalette {
  const PlotterPalette({
    required this.spaceFill,
    required this.combiningFill,
    required this.hiFill,
    required this.hiStroke,
    required this.loStroke,
    required this.hintStroke,
    required this.hintAltStroke,
    required this.fontColor,
    required this.axisColor,
  });

  final Color spaceFill;
  final Color combiningFill;
  final Color hiFill;
  final Color hiStroke;
  final Color loStroke;
  final Color hintStroke;
  final Color hintAltStroke;
  final Color fontColor;
  final Color axisColor;

  factory PlotterPalette.fromColors(QAppColors colors) {
    final dark = colors.isDark;
    final space =
        dark ? const Color(0xFF101216) : const Color(0xFFFAFAFA);
    final hi = colors.success;
    final lo = colors.danger;
    final hint = colors.info;
    return PlotterPalette(
      spaceFill: space,
      combiningFill: Color.alphaBlend(
        hint.withValues(alpha: dark ? 0.20 : 0.12),
        space,
      ),
      hiFill: Color.alphaBlend(
        hi.withValues(alpha: dark ? 0.24 : 0.18),
        space,
      ),
      hiStroke: hi,
      loStroke: lo,
      hintStroke: hint.withValues(alpha: dark ? 0.85 : 0.65),
      hintAltStroke: lo.withValues(alpha: dark ? 0.85 : 0.70),
      fontColor: colors.textPrimary,
      axisColor: colors.textMuted,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlotterPalette &&
      other.spaceFill == spaceFill &&
      other.combiningFill == combiningFill &&
      other.hiFill == hiFill &&
      other.hiStroke == hiStroke &&
      other.loStroke == loStroke &&
      other.hintStroke == hintStroke &&
      other.hintAltStroke == hintAltStroke &&
      other.fontColor == fontColor &&
      other.axisColor == axisColor;

  @override
  int get hashCode => Object.hash(
        spaceFill,
        combiningFill,
        hiFill,
        hiStroke,
        loStroke,
        hintStroke,
        hintAltStroke,
        fontColor,
        axisColor,
      );
}

class PulsePlotterPainter extends CustomPainter {
  PulsePlotterPainter({
    required this.pulses,
    required this.dataWidth,
    required this.hints,
    required this.altHints,
    required this.zoom,
    required this.left,
    required this.palette,
  });

  final List<double> pulses;
  final double dataWidth;
  final List<Hint> hints;
  final List<Hint> altHints;
  final double zoom;
  final double left;
  final PlotterPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    if (width <= 0) return;
    final height = kPlotHeight;
    final barHeight = height - _marginTop - _marginBottom;

    final k = zoom;
    final maxZoom = dataWidth > 0 ? math.max(1.0, dataWidth / width) : 1.0;
    final tx = -left * width * k;
    final sf = k / maxZoom;

    _fill(canvas, 0, -1, width, barHeight + _marginTop + _marginBottom,
        palette.spaceFill);

    final maxRightSide = width * k;
    final pulseInOneX = dataWidth / maxRightSide;
    final leftSide = (tx * -1).truncate().toDouble();
    final rightSide = (tx * -1 + width).truncate().toDouble();
    final leftPulse = leftSide * pulseInOneX;
    final rightPulse = rightSide * pulseInOneX;

    var prevX = 0.0;
    var skipPulse = 0;
    var sum = 0.0;

    List<double> visible;
    if (k < _breakpointZoom) {
      visible = _combiningPulses(pulses, pulseInOneX);
    } else {
      visible = pulses;
    }
    final filtered =
        _filterPulses(visible, sum, prevX, skipPulse, leftPulse, rightPulse);
    visible = filtered.pulses;
    sum = filtered.sum;
    prevX = filtered.prevX;
    skipPulse = filtered.skipPulse;

    for (var i = 0; i < visible.length; i++) {
      final x = visible[i];
      if (x == 0) continue;

      final even = (i + skipPulse) % 2 == 0;
      if (even) {
        _fill(
          canvas,
          prevX * sf + tx,
          _marginTop,
          x * sf,
          barHeight,
          k < _breakpointZoom ? palette.combiningFill : palette.hiFill,
        );
        final y = height - barHeight - _marginTop + _hiLine / 2;
        _line(canvas, prevX * sf + tx, y, (prevX + x) * sf + tx, y, _hiLine,
            palette.hiStroke);
      } else {
        final y = height - _marginTop - _loLine / 2;
        _line(canvas, prevX * sf + tx, y, (prevX + x) * sf + tx, y, _loLine,
            palette.loStroke);
      }

      final w = x * ((width * k) / dataWidth);
      final labelX = (prevX + x / 2) * sf + tx;
      if (w > _fontSize * 4) {
        _text(canvas, _label(x), labelX, height / 2);
      } else if (w > _fontSize * 0.8) {
        _textVertical(canvas, _label(x), labelX, height / 2);
      }

      if (pulseInOneX <= _breakpointPulseInOneX &&
          k >= _breakpointZoom &&
          even) {
        _line(
          canvas,
          prevX * sf + tx,
          height - _marginTop,
          prevX * sf + tx,
          height - barHeight - _marginTop,
          _edgeLine,
          palette.hiStroke,
        );
        _line(
          canvas,
          (prevX + x) * sf + tx,
          height - barHeight - _marginTop,
          (prevX + x) * sf + tx,
          height - _marginTop,
          _edgeLine,
          palette.loStroke,
        );
      }

      prevX += x;
    }

    _drawAllHints(canvas, sf, tx, height, leftPulse, rightPulse);
    _drawAxis(canvas, width, sf, tx, k);
  }

  void _drawAllHints(Canvas canvas, double sf, double tx, double height,
      double leftPulse, double rightPulse) {
    bool inRange(Hint d) {
      if (d.x0 >= leftPulse && d.x0 <= rightPulse) return true;
      if (d.x1 >= leftPulse && d.x1 <= rightPulse) return true;
      return false;
    }

    final hs = hints.where(inRange).toList();
    double? prevHint;
    for (final hint in hs) {
      if (prevHint != hint.x0 && hint.x0 >= 0 && hint.x0 < dataWidth) {
        _hintLineAt(
            canvas, hint.x0 * sf + tx, height, _hintLine, palette.hintStroke);
      }
      if (hint.x1 >= 0 && hint.x1 < dataWidth) {
        _hintLineAt(
            canvas, hint.x1 * sf + tx, height, _hintLine, palette.hintStroke);
      }
      prevHint = hint.x1;
    }

    final alt = altHints.where(inRange).toList();
    prevHint = null;
    for (final hint in alt) {
      if (prevHint != hint.x0 && hint.x0 >= 0 && hint.x0 < dataWidth) {
        _hintLineAt(canvas, hint.x0 * sf + tx, height, _hintAltLine,
            palette.hintAltStroke);
      }
      if (hint.x1 >= 0 && hint.x1 < dataWidth) {
        _hintLineAt(canvas, hint.x1 * sf + tx, height, _hintAltLine,
            palette.hintAltStroke);
      }
      prevHint = hint.x1;
    }
  }

  void _drawAxis(
      Canvas canvas, double width, double sf, double tx, double k) {
    if (sf <= 0) return;
    final d0 = (0 - tx) / sf;
    final d1 = (width - tx) / sf;
    if (!d0.isFinite || !d1.isFinite || d1 <= d0) return;

    final tickCount = math.max(2, (width / 100).floor());
    final step = _niceStep((d1 - d0) / tickCount);
    if (step <= 0 || !step.isFinite) return;

    final range = autorange(dataWidth / k);
    final timeRange = autorangeTime(dataWidth / 1e6 / k);

    final paint = Paint()
      ..color = palette.axisColor
      ..strokeWidth = 1;

    var t = (d0 / step).ceil() * step;
    var guard = 0;
    while (t <= d1 && guard < 1000) {
      guard++;
      final sx = t * sf + tx;
      canvas.drawLine(Offset(sx, 0), Offset(sx, 6), paint);
      _axisLabel(canvas, _formatTick(t, range, timeRange), sx);
      t += step;
    }
  }

  void _axisLabel(Canvas canvas, String text, double cx) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: palette.axisColor, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, 8));
  }

  String _formatTick(double value, AutoRange range, AutoRange timeRange) {
    var s = (value / range.scale).toStringAsFixed(2);
    if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
    return '$s${timeRange.prefix}';
  }

  double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 0;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    final norm = raw / magnitude;
    final double nice;
    if (norm < 1.5) {
      nice = 1;
    } else if (norm < 3) {
      nice = 2;
    } else if (norm < 7) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  void _fill(Canvas canvas, double x, double y, double w, double h,
      Color color) {
    if (!x.isFinite || !y.isFinite || !w.isFinite || !h.isFinite) return;
    canvas.drawRect(
      Rect.fromLTWH(x, y, w, h),
      Paint()..color = color,
    );
  }

  void _line(Canvas canvas, double x0, double y0, double x1, double y1,
      double lineWidth, Color color) {
    if (!x0.isFinite || !y0.isFinite || !x1.isFinite || !y1.isFinite) return;
    canvas.drawLine(
      Offset(x0, y0),
      Offset(x1, y1),
      Paint()
        ..color = color
        ..strokeWidth = lineWidth,
    );
  }

  void _hintLineAt(Canvas canvas, double x, double height, double lineWidth,
      Color color) {
    if (!x.isFinite) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = lineWidth;
    const dashOn = 3.0;
    const dashOff = 2.0;
    var y = 0.0;
    while (y < height) {
      final end = math.min(y + dashOn, height);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y = end + dashOff;
    }
  }

  void _text(Canvas canvas, String text, double cx, double cy) {
    if (!cx.isFinite || !cy.isFinite) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: palette.fontColor, fontSize: _fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _textVertical(Canvas canvas, String text, double cx, double cyCenter) {
    if (!cx.isFinite || !cyCenter.isFinite) return;
    const lineStep = _fontSize + 2;
    final total = text.length * lineStep;
    var y = cyCenter - total / 2;
    for (final ch in text.split('')) {
      final tp = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(color: palette.fontColor, fontSize: _fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, y + (lineStep - tp.height) / 2));
      y += lineStep;
    }
  }

  String _label(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static List<double> _combiningPulses(
      List<double> data, double pulseInOneX) {
    final pulses = <double>[];
    var prevX = 0.0;
    for (var i = 0; i < data.length; i++) {
      if (i % 2 != 0) {
        if (data[i] >= pulseInOneX * 10) {
          pulses.add(prevX);
          pulses.add(data[i]);
          prevX = 0;
          continue;
        }
      }
      prevX += data[i];
    }
    if (prevX != 0) {
      pulses.add(prevX);
    }
    return pulses;
  }

  static ({List<double> pulses, double sum, double prevX, int skipPulse})
      _filterPulses(List<double> data, double sum, double prevX, int skipPulse,
          double leftPulse, double rightPulse) {
    final pulses = <double>[];
    for (final d in data) {
      final minX = sum;
      sum += d;
      final maxX = sum;
      if (maxX >= leftPulse && minX <= rightPulse) {
        pulses.add(d);
        continue;
      }
      if (minX < leftPulse) {
        prevX += d;
        skipPulse += 1;
      }
    }
    return (pulses: pulses, sum: sum, prevX: prevX, skipPulse: skipPulse);
  }

  @override
  bool shouldRepaint(covariant PulsePlotterPainter old) {
    return old.pulses != pulses ||
        old.hints != hints ||
        old.altHints != altHints ||
        old.zoom != zoom ||
        old.left != left ||
        old.palette != palette;
  }
}
