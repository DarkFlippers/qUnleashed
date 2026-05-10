import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;

import '../../theme.dart';
import 'models/models.dart';

const int kFlipperScreenWidth = 128;
const int kFlipperScreenHeight = 64;

Future<DecodedFrame> decodeScreenFrame(ScreenFrame frame) async {
  final pixels = Uint8List(kFlipperScreenWidth * kFlipperScreenHeight * 4);
  final raw = frame.data;
  final bg = FlipperOriginalColors.flipperScreenBackground.toARGB32();
  final fg = FlipperOriginalColors.flipperScreenBorder.toARGB32();

  final orientation = switch (frame.orientation) {
    ScreenOrientation.HORIZONTAL => StreamOrientation.horizontal,
    ScreenOrientation.HORIZONTAL_FLIP => StreamOrientation.horizontalFlip,
    ScreenOrientation.VERTICAL => StreamOrientation.vertical,
    ScreenOrientation.VERTICAL_FLIP => StreamOrientation.verticalFlip,
    _ => StreamOrientation.horizontal,
  };

  final flipped = orientation == StreamOrientation.horizontalFlip ||
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
    }
  }

  final image = await _imageFromPixels(pixels);
  final pngBytes =
      (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  return DecodedFrame(image: image, pngBytes: pngBytes, orientation: orientation);
}

Future<ui.Image> _imageFromPixels(Uint8List pixels) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    kFlipperScreenWidth,
    kFlipperScreenHeight,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
