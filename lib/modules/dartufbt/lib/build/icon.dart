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
    final bytes = file.readAsBytesSync();
    final decoder = _decoderFor(bytes);
    final decoded = decoder == null
        ? img.decodeImage(bytes)
        : decoder.decode(bytes);
    if (decoded == null) {
      throw FormatException('Failed to decode image ${file.path}');
    }
    // Netpbm bitmaps store 1 as black, PnmDecoder hands it back as white while
    // PIL, which fbt builds with, keeps it black.
    if (_isPbm(bytes)) img.invert(decoded);
    return toImage(decoded);
  }

  /// Picks the decoder by file signature, the way PIL does for fbt. Sniffing it
  /// with `decodeImage` is not enough: its TGA probe accepts anything short,
  /// so a Netpbm `.icon` is decoded as TGA and blows up mid-stream.
  static img.Decoder? _decoderFor(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return img.PngDecoder();
    }
    if (bytes[0] == 0x50 &&
        const [0x31, 0x32, 0x33, 0x35, 0x36].contains(bytes[1])) {
      return img.PnmDecoder();
    }
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return img.BmpDecoder();
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return img.JpegDecoder();
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return img.GifDecoder();
    }
    return null;
  }

  static bool _isPbm(Uint8List bytes) =>
      bytes.length > 1 && bytes[0] == 0x50 && bytes[1] == 0x31;

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
