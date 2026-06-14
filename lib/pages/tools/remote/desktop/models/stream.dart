import 'dart:typed_data';

enum StreamOrientation {
  horizontal,
  horizontalFlip,
  vertical,
  verticalFlip,
}

/// Synchronously decoded Flipper screen frame.
/// Contains raw pixel data without any GPU resources — safe across async boundaries.
class RawFrameData {
  const RawFrameData({
    required this.pixelIndices,
    required this.rgba,
    required this.bgColor,
    required this.fgColor,
    required this.orientation,
  });

  /// Flat 128×64 pixel indices: 0 = background, 1 = foreground.
  final Uint8List pixelIndices;

  /// Flat 128×64×4 RGBA buffer for GPU image creation.
  final Uint8List rgba;

  final int bgColor; // ARGB: 0xAARRGGBB
  final int fgColor; // ARGB: 0xAARRGGBB
  final StreamOrientation orientation;
}
