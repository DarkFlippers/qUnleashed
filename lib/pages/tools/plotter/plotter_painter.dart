import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'analysis/autorange.dart';
import 'analysis/slicer.dart';

const double kPlotHeight = 300;
const double _marginTop = 50;
const double _marginBottom = 50;
const double _breakpointZoom = 10;
const double _breakpointPulseInOneX = 75;

const Color _spaceFill = Color(0xFFFAFAFA);
const Color _combiningFill = Color(0xFFE6ECEE);
const Color _hiFill = Color(0xFFE0EFE0);
const Color _hiStroke = Color(0xFF33CC33);
const double _hiLine = 4;
const Color _loStroke = Color(0xFFCC3333);
const double _loLine = 4;
const double _edgeLine = 1;
const double _hintLine = 1;
const Color _hintStroke = Color(0xFFAAAAFF);
const double _hintAltLine = 3;
const Color _hintAltStroke = Color(0xFFCC5555);
const double _fontSize = 10;
const Color _fontColor = Color(0xFF000000);
const Color _axisColor = Color(0xFF888888);

class PlotTransform {
  const PlotTransform(this.k, this.x);

  final double k;
  final double x;
}

class PulsePlotterPainter extends CustomPainter {
  PulsePlotterPainter({
    required this.pulses,
    required this.dataWidth,
    required this.hints,
    required this.altHints,
    required this.transform,
    required this.maxZoom,
  });

  final List<double> pulses;
  final double dataWidth;
  final List<Hint> hints;
  final List<Hint> altHints;
  final PlotTransform transform;
  final double maxZoom;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = kPlotHeight;
    final barHeight = height - _marginTop - _marginBottom;
    final k = transform.k;
    final tx = transform.x;
    final sf = k / maxZoom;

    _fill(canvas, 0, -1, width, barHeight + _marginTop + _marginBottom,
        _spaceFill);

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
          k < _breakpointZoom ? _combiningFill : _hiFill,
        );
        final y = height - barHeight - _marginTop + _hiLine / 2;
        _line(canvas, prevX * sf + tx, y, (prevX + x) * sf + tx, y, _hiLine,
            _hiStroke);
      } else {
        final y = height - _marginTop - _loLine / 2;
        _line(canvas, prevX * sf + tx, y, (prevX + x) * sf + tx, y, _loLine,
            _loStroke);
      }

      final w = x * ((width * k) / dataWidth);
      if (w > _fontSize * 4) {
        _text(
          canvas,
          _label(x),
          (prevX + x / 2) * sf + tx,
          height / 2,
        );
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
          _hiStroke,
        );
        _line(
          canvas,
          (prevX + x) * sf + tx,
          height - barHeight - _marginTop,
          (prevX + x) * sf + tx,
          height - _marginTop,
          _edgeLine,
          _loStroke,
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
        _hintLineAt(canvas, hint.x0 * sf + tx, height, _hintLine, _hintStroke);
      }
      if (hint.x1 >= 0 && hint.x1 < dataWidth) {
        _hintLineAt(canvas, hint.x1 * sf + tx, height, _hintLine, _hintStroke);
      }
      prevHint = hint.x1;
    }

    final alt = altHints.where(inRange).toList();
    prevHint = null;
    for (final hint in alt) {
      if (prevHint != hint.x0 && hint.x0 >= 0 && hint.x0 < dataWidth) {
        _hintLineAt(
            canvas, hint.x0 * sf + tx, height, _hintAltLine, _hintAltStroke);
      }
      if (hint.x1 >= 0 && hint.x1 < dataWidth) {
        _hintLineAt(
            canvas, hint.x1 * sf + tx, height, _hintAltLine, _hintAltStroke);
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
      ..color = _axisColor
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
        style: const TextStyle(color: _axisColor, fontSize: 9),
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
        style: const TextStyle(color: _fontColor, fontSize: _fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
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
        old.transform.k != transform.k ||
        old.transform.x != transform.x ||
        old.maxZoom != maxZoom;
  }
}
