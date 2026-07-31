import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'heatshrink.dart';

class FlipperImage {
  const FlipperImage({
    required this.width,
    required this.height,
    required this.xbm,
    required this.data,
  });

  final int width;
  final int height;
  final Uint8List xbm;
  final Uint8List data;

  bool get isCompressed => data.isNotEmpty && data[0] == 0x01;
}

class IconCodec {
  const IconCodec({this.heatshrink = const Heatshrink()});

  final Heatshrink heatshrink;

  FlipperImage fileToImage(File file) {
    final decoded = img.decodeImage(file.readAsBytesSync());
    if (decoded == null) {
      throw FormatException('Failed to decode image ${file.path}');
    }
    return toImage(decoded);
  }

  FlipperImage toImage(img.Image source) {
    final xbm = _toXbm(source);
    final compressed = heatshrink.compress(xbm);

    final framed = Uint8List(compressed.length + 2);
    framed[0] = compressed.length & 0xFF;
    framed[1] = (compressed.length >> 8) & 0xFF;
    framed.setRange(2, framed.length, compressed);

    final Uint8List data;
    if (framed.length + 2 < xbm.length + 1) {
      data = Uint8List(framed.length + 2)
        ..[0] = 0x01
        ..[1] = 0x00
        ..setRange(2, framed.length + 2, framed);
    } else {
      data = Uint8List(xbm.length + 1)
        ..[0] = 0x00
        ..setRange(1, xbm.length + 1, xbm);
    }

    return FlipperImage(
      width: source.width,
      height: source.height,
      xbm: xbm,
      data: data,
    );
  }

  static Uint8List _toXbm(img.Image source) {
    final rowBytes = (source.width + 7) >> 3;
    final out = Uint8List(rowBytes * source.height);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        if (!_isInk(source, x, y)) continue;
        out[y * rowBytes + (x >> 3)] |= 1 << (x & 7);
      }
    }
    return out;
  }

  static bool _isInk(img.Image source, int x, int y) {
    final pixel = source.getPixel(x, y);
    final max = pixel.maxChannelValue.toDouble();
    if (max <= 0) return false;
    if (source.hasAlpha && pixel.a / max < 0.5) return false;

    final luminance = source.numChannels >= 3
        ? (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / max
        : pixel.r / max;
    return luminance < 0.5;
  }
}
