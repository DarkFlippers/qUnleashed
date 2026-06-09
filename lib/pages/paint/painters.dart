import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'constants.dart';

class CanvasPainter extends CustomPainter {
  const CanvasPainter({
    required this.pixels,
    required this.pixelSize,
    required this.fgColor,
    required this.bgColor,
    required this.previewColor,
    required this.version,
    this.previewPixels,
    this.previewFg = true,
    this.showGrid = false,
    this.onionPixels,
  });

  final Uint8List pixels;
  final double pixelSize;
  final Color fgColor;
  final Color bgColor;
  final Color previewColor;
  final int version;
  final List<int>? previewPixels;
  final bool previewFg;
  final bool showGrid;
  final Uint8List? onionPixels;

  Rect _pixelRect(int x, int y) {
    final l = (x * pixelSize).roundToDouble();
    final t = (y * pixelSize).roundToDouble();
    final r = ((x + 1) * pixelSize).roundToDouble();
    final b = ((y + 1) * pixelSize).roundToDouble();
    return Rect.fromLTRB(l, t, r, b);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    if (onionPixels != null) {
      final paint = Paint()
        ..color = fgColor.withAlpha(28)
        ..isAntiAlias = false;
      for (int y = 0; y < kCanvasHeight; y++) {
        for (int x = 0; x < kCanvasWidth; x++) {
          if (onionPixels![y * kCanvasWidth + x] != 0) {
            canvas.drawRect(_pixelRect(x, y), paint);
          }
        }
      }
    }

    final fgPaint = Paint()
      ..color = fgColor
      ..isAntiAlias = false;
    final previewSet = previewPixels != null ? Set<int>.from(previewPixels!) : const <int>{};

    for (int y = 0; y < kCanvasHeight; y++) {
      for (int x = 0; x < kCanvasWidth; x++) {
        final idx = y * kCanvasWidth + x;
        final draw = previewSet.contains(idx) ? previewFg : pixels[idx] != 0;
        if (draw) canvas.drawRect(_pixelRect(x, y), fgPaint);
      }
    }

    if (previewPixels != null && previewPixels!.isNotEmpty) {
      final paint = Paint()
        ..color = previewColor.withAlpha(180)
        ..isAntiAlias = false;
      for (final idx in previewPixels!) {
        canvas.drawRect(_pixelRect(idx % kCanvasWidth, idx ~/ kCanvasWidth), paint);
      }
    }

    if (showGrid) {
      final paint = Paint()
        ..color = Colors.black.withAlpha(30)
        ..strokeWidth = 0.5;
      for (int x = 0; x <= kCanvasWidth; x++) {
        canvas.drawLine(
          Offset(x * pixelSize, 0),
          Offset(x * pixelSize, kCanvasHeight * pixelSize),
          paint,
        );
      }
      for (int y = 0; y <= kCanvasHeight; y++) {
        canvas.drawLine(
          Offset(0, y * pixelSize),
          Offset(kCanvasWidth * pixelSize, y * pixelSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CanvasPainter old) =>
      old.version != version ||
      old.previewPixels != previewPixels ||
      old.pixelSize != pixelSize ||
      old.showGrid != showGrid ||
      old.onionPixels != onionPixels;
}

class ThumbnailPainter extends CustomPainter {
  const ThumbnailPainter({
    required this.pixels,
    required this.fgColor,
    required this.bgColor,
    required this.version,
  });

  final Uint8List pixels;
  final Color fgColor;
  final Color bgColor;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);
    final pw = size.width / kCanvasWidth;
    final ph = size.height / kCanvasHeight;
    final paint = Paint()..color = fgColor;
    for (int y = 0; y < kCanvasHeight; y++) {
      for (int x = 0; x < kCanvasWidth; x++) {
        if (pixels[y * kCanvasWidth + x] != 0) {
          canvas.drawRect(Rect.fromLTWH(x * pw, y * ph, pw, ph), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(ThumbnailPainter old) =>
      old.version != version || old.fgColor != fgColor;
}
