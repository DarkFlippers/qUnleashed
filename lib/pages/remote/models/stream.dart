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
    required this.orientation,
  });

  final ui.Image image;
  final Uint8List pngBytes;
  final StreamOrientation orientation;
}
