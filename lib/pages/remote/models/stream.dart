import 'dart:typed_data';
import 'dart:ui' as ui;

enum StreamOrientation {
  horizontal,
  horizontalFlip,
  vertical,
  verticalFlip,
}

class DecodedFrame {
  const DecodedFrame({
    required this.image,
    required this.pngBytes,
    required this.pixelIndices,
    required this.bgColor,
    required this.fgColor,
    required this.orientation,
  });

  final ui.Image image;
  final Uint8List pngBytes;
  /// Flat array of 128×64 pixel indices: 0 = background, 1 = foreground.
  final Uint8List pixelIndices;
  final int bgColor; // ARGB: 0xAARRGGBB
  final int fgColor; // ARGB: 0xAARRGGBB
  final StreamOrientation orientation;
}
