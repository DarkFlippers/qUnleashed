import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;

import '../../../../theme/colors/display.dart';
import 'models/models.dart';

const int kFlipperScreenWidth = 128;
const int kFlipperScreenHeight = 64;

/// Synchronously unpacks a [ScreenFrame] into raw pixel data.
/// No GPU or async work - runs immediately on any incoming frame.
RawFrameData decodeFrameSync(ScreenFrame frame) {
  final pixels = Uint8List(kFlipperScreenWidth * kFlipperScreenHeight * 4);
  final pixelIndices = Uint8List(kFlipperScreenWidth * kFlipperScreenHeight);
  final raw = frame.data;
  final display = DisplayColors.current;
  final bg = display.background.toARGB32();
  final fg = display.foreground.toARGB32();

  final orientation = switch (frame.orientation) {
    ScreenOrientation.HORIZONTAL => StreamOrientation.horizontal,
    ScreenOrientation.HORIZONTAL_FLIP => StreamOrientation.horizontalFlip,
    ScreenOrientation.VERTICAL => StreamOrientation.vertical,
    ScreenOrientation.VERTICAL_FLIP => StreamOrientation.verticalFlip,
    _ => StreamOrientation.horizontal,
  };

  final flipped =
      orientation == StreamOrientation.horizontalFlip ||
      orientation == StreamOrientation.verticalFlip;

  for (var x = 0; x < kFlipperScreenWidth; x++) {
    for (var y = 0; y < kFlipperScreenHeight; y++) {
      final idx = ((y ~/ 8) * kFlipperScreenWidth) + x;
      final bit = 1 << (y & 7);
      final isSet = idx < raw.length && (raw[idx] & bit) != 0;

      final bx = flipped ? kFlipperScreenWidth - x - 1 : x;
      final by = flipped ? kFlipperScreenHeight - y - 1 : y;
      final pi = ((by * kFlipperScreenWidth) + bx) * 4;

      final color = isSet ? fg : bg;
      pixels[pi] = (color >> 16) & 0xFF;
      pixels[pi + 1] = (color >> 8) & 0xFF;
      pixels[pi + 2] = color & 0xFF;
      pixels[pi + 3] = (color >> 24) & 0xFF;
      pixelIndices[by * kFlipperScreenWidth + bx] = isSet ? 1 : 0;
    }
  }

  return RawFrameData(
    pixelIndices: pixelIndices,
    rgba: pixels,
    bgColor: bg,
    fgColor: fg,
    orientation: orientation,
  );
}

/// Asynchronously creates a [ui.Image] from pre-decoded RGBA pixel data.
/// Runs in the engine thread; does not block the Dart isolate.
Future<ui.Image> createImageFromRgba(Uint8List rgba) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    kFlipperScreenWidth,
    kFlipperScreenHeight,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
