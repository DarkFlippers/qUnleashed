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
    final compressed = _lzwCompress(indices, minCodeSize);

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

  /// GIF codes are at most 12 bits wide, so 4096 is one past the last code.
  /// The two are the same fact, so they are derived from one another rather
  /// than written out twice and left to drift.
  static const int _maxCodeSize = 12;
  static const int _maxCode = 1 << _maxCodeSize;

  /// GIF LZW compression.
  ///
  /// What was here before did not compress at all. It emitted a clear code
  /// before every *pair* of pixels, so two one-bit pixels cost three 3-bit
  /// codes - 4.5 bits per pixel of 1-bit data, a four-and-a-half-fold
  /// expansion of the thing it was meant to shrink. The stated reason was to
  /// avoid a desynchronised LZW table showing as a blank frame; the way to
  /// avoid that is to widen the code at exactly the point the decoder does,
  /// which is what this does and what the round-trip tests pin.
  static Uint8List _lzwCompress(Uint8List indices, int minCodeSize) {
    final clearCode = 1 << minCodeSize;
    final eoiCode = clearCode + 1;
    final writer = _LsbBitWriter();

    var codeSize = minCodeSize + 1;
    var nextCode = eoiCode + 1;
    // Keyed on (prefix << 8) | pixel: a pixel is a palette index under 256 and
    // a prefix code never exceeds 4095, so the pair fits one int.
    var table = <int, int>{};

    writer.write(clearCode, codeSize);
    if (indices.isEmpty) {
      writer.write(eoiCode, codeSize);
      writer.flush();
      return writer.bytes();
    }

    var prefix = indices[0] & 0xFF;
    for (var i = 1; i < indices.length; i++) {
      final pixel = indices[i] & 0xFF;
      final known = table[(prefix << 8) | pixel];
      if (known != null) {
        prefix = known;
        continue;
      }
      writer.write(prefix, codeSize);
      if (nextCode < _maxCode) {
        table[(prefix << 8) | pixel] = nextCode;
        nextCode++;
        // Widen one code later than the table filling up, because the
        // decoder's table always lags this one by a single entry: it adds an
        // entry only once it has read the *following* code, and the code after
        // a clear adds nothing at all. Widening when this table fills - the
        // obvious rule - makes every decoder read the stream one code out of
        // step, which is exactly the garbled output the old literal stream was
        // written to avoid.
        // The width cap cannot actually be reached, because the reset below
        // fires first; it is here so the two limits stay consistent if
        // _maxCode ever moves.
        if (nextCode == (1 << codeSize) + 1 && codeSize < _maxCodeSize) {
          codeSize++;
        }
      } else {
        // Table full. Both sides start over rather than let codes outgrow the
        // 12 bits GIF allows.
        writer.write(clearCode, codeSize);
        table = <int, int>{};
        codeSize = minCodeSize + 1;
        nextCode = eoiCode + 1;
      }
      prefix = pixel;
    }

    writer.write(prefix, codeSize);
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
