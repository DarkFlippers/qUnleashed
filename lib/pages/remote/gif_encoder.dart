import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart GIF89a encoder for 2-color (monochrome) animations.
///
/// Designed for 128×64 Flipper Zero screen recordings.
/// Uses LZW compression with LSB-first bit packing per the GIF89a spec.
class FlipperGifEncoder {
  /// Encodes frames into an animated GIF89a byte sequence.
  ///
  /// [frames]   — pixel index arrays (values 0 or 1), each [width]×[height] long.
  /// [delaysMs] — per-frame delay in milliseconds.
  /// [color0]   — background color as 0xAARRGGBB.
  /// [color1]   — foreground color as 0xAARRGGBB.
  static Uint8List encode({
    required int width,
    required int height,
    required List<Uint8List> frames,
    required List<int> delaysMs,
    required int color0,
    required int color1,
    int scale = 1,
  }) {
    assert(frames.length == delaysMs.length);
    assert(scale >= 1);
    final buf = BytesBuilder();
    final outputWidth = width * scale;
    final outputHeight = height * scale;

    // GIF89a header
    buf.add(ascii.encode('GIF89a'));
    _le16(buf, outputWidth);
    _le16(buf, outputHeight);
    buf.addByte(0x00); // no global color table
    buf.addByte(0x00); // background color index
    buf.addByte(0x00); // pixel aspect ratio

    // Netscape Application Extension — infinite loop
    buf.addByte(0x21);
    buf.addByte(0xFF);
    buf.addByte(11);
    buf.add(ascii.encode('NETSCAPE2.0'));
    buf.addByte(3); // sub-block size
    buf.addByte(1); // sub-block ID
    _le16(buf, 0); // loop count 0 = infinite
    buf.addByte(0); // block terminator

    for (var i = 0; i < frames.length; i++) {
      final indices = scale == 1
          ? frames[i]
          : _scaleIndices(frames[i], width, height, scale);
      _writeFrame(
        buf,
        outputWidth,
        outputHeight,
        indices,
        delaysMs[i],
        color0,
        color1,
      );
    }

    buf.addByte(0x3B); // GIF trailer
    return buf.toBytes();
  }

  static void _writeFrame(
    BytesBuilder buf,
    int width,
    int height,
    Uint8List indices,
    int delayMs,
    int color0,
    int color1,
  ) {
    // GIF delay is in centiseconds (1/100 s); clamp to valid range.
    final cs = (delayMs / 10).round().clamp(1, 65535);

    // Graphic Control Extension
    buf.addByte(0x21);
    buf.addByte(0xF9);
    buf.addByte(0x04); // block size
    buf.addByte(0x00); // packed: no dispose, no user input, no transparent
    _le16(buf, cs);
    buf.addByte(0x00); // transparent color index (unused)
    buf.addByte(0x00); // block terminator

    // Image Descriptor
    buf.addByte(0x2C); // image separator
    _le16(buf, 0); // left
    _le16(buf, 0); // top
    _le16(buf, width);
    _le16(buf, height);
    // Packed byte: M=1 (local color table present), I=0, S=0, size=0 → 2^(0+1)=2 colors
    buf.addByte(0x80);

    // Local Color Table: 2 colors × 3 RGB bytes = 6 bytes
    buf.addByte((color0 >> 16) & 0xFF);
    buf.addByte((color0 >> 8) & 0xFF);
    buf.addByte(color0 & 0xFF);
    buf.addByte((color1 >> 16) & 0xFF);
    buf.addByte((color1 >> 8) & 0xFF);
    buf.addByte(color1 & 0xFF);

    // Image Data
    const minCodeSize = 2; // GIF spec minimum; matches 2-color palette
    buf.addByte(minCodeSize);
    final compressed = _lzwLiteralCompress(indices, minCodeSize);

    // Pack into sub-blocks of at most 255 bytes each
    var offset = 0;
    while (offset < compressed.length) {
      final sz = (compressed.length - offset).clamp(0, 255);
      buf.addByte(sz);
      buf.add(compressed.sublist(offset, offset + sz));
      offset += sz;
    }
    buf.addByte(0x00); // block terminator
  }

  static void _le16(BytesBuilder buf, int v) {
    buf.addByte(v & 0xFF);
    buf.addByte((v >> 8) & 0xFF);
  }

  static Uint8List _scaleIndices(
    Uint8List source,
    int width,
    int height,
    int scale,
  ) {
    final outWidth = width * scale;
    final outHeight = height * scale;
    final out = Uint8List(outWidth * outHeight);
    for (var y = 0; y < outHeight; y++) {
      final srcY = y ~/ scale;
      final srcRow = srcY * width;
      final outRow = y * outWidth;
      for (var x = 0; x < outWidth; x++) {
        out[outRow + x] = source[srcRow + (x ~/ scale)];
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // GIF LZW compression
  // ---------------------------------------------------------------------------

  static Uint8List _lzwLiteralCompress(Uint8List indices, int minCodeSize) {
    final clearCode = 1 << minCodeSize; // 4 for minCodeSize=2
    final eoiCode = clearCode + 1; // 5
    final writer = _LsbBitWriter();

    // The Flipper screen is only 128x64 and 2-color, so a deliberately simple
    // literal stream is preferable to a fragile table compressor here. We emit
    // a clear code before each pair of pixels, which keeps the decoder's code
    // size at 3 bits for the entire frame and avoids GIF viewers receiving a
    // desynchronized LZW table as a blank/white frame.
    final codeSize = minCodeSize + 1;
    for (var i = 0; i < indices.length; i += 2) {
      writer.write(clearCode, codeSize);
      writer.write(indices[i] & 0x01, codeSize);
      if (i + 1 < indices.length) {
        writer.write(indices[i + 1] & 0x01, codeSize);
      }
    }
    writer.write(eoiCode, codeSize);
    writer.flush();
    return writer.bytes();
  }
}

/// Writes integers LSB-first into a byte buffer (GIF bit packing).
class _LsbBitWriter {
  final _buf = <int>[];
  int _bits = 0;
  int _count = 0;

  void write(int value, int numBits) {
    _bits |= value << _count;
    _count += numBits;
    while (_count >= 8) {
      _buf.add(_bits & 0xFF);
      _bits >>= 8;
      _count -= 8;
    }
  }

  void flush() {
    if (_count > 0) {
      _buf.add(_bits & 0xFF);
      _bits = 0;
      _count = 0;
    }
  }

  Uint8List bytes() => Uint8List.fromList(_buf);
}
