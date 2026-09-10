import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart GIF89a encoder for 2-color (monochrome) animations.
///
/// Designed for 128×64 Flipper Zero screen recordings.
/// Uses LZW compression with LSB-first bit packing per the GIF89a spec.
class FlipperGifEncoder {
  /// A two-colour palette needs a 2-bit minimum code size, which is also the
  /// smallest the format permits. Fixing it here rather than threading it
  /// around is what lets the code table below be sized to the palette.
  static const int _minCodeSize = 2;
  static const int _clearCode = 1 << _minCodeSize;
  static const int _eoiCode = _clearCode + 1;
  static const int _firstFreeCode = _eoiCode + 1;

  /// Codes are at most 12 bits, so this is one past the last usable one.
  static const int _maxCodeSize = 12;
  static const int _maxCode = 1 << _maxCodeSize;

  /// The palette has two entries. Masking to it keeps a caller's stray index
  /// out of the code stream, where it would not be a wrong colour but a
  /// structural break: index 4 is the clear code and index 5 is end-of-input,
  /// either of which derails the decoder mid-frame.
  static const int _paletteMask = 1;

  /// One slot per (prefix, pixel) pair. Keying on the palette width rather
  /// than on a whole byte keeps the table at 64KB instead of 4MB, which is the
  /// difference between it living in cache and not.
  static const int _tableSlots = _maxCode << _minCodeSize;

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

    // Allocated once and reused: frames are compressed independently, but
    // there is no reason to hand the collector a fresh 64KB per frame to do it.
    final table = Int32List(_tableSlots);
    final scaled = scale == 1 ? null : Uint8List(outputWidth * outputHeight);

    for (var i = 0; i < frames.length; i++) {
      final indices = scaled == null
          ? frames[i]
          : _scaleInto(scaled, frames[i], width, height, scale);
      _writeFrame(
        buf,
        outputWidth,
        outputHeight,
        indices,
        delaysMs[i],
        color0,
        color1,
        table,
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
    Int32List table,
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
    buf.addByte(_minCodeSize);
    final compressed = _lzwCompress(indices, table);

    // Pack into sub-blocks of at most 255 bytes each
    var offset = 0;
    while (offset < compressed.length) {
      final sz = (compressed.length - offset).clamp(0, 255);
      buf.addByte(sz);
      buf.add(Uint8List.sublistView(compressed, offset, offset + sz));
      offset += sz;
    }
    buf.addByte(0x00); // block terminator
  }

  static void _le16(BytesBuilder buf, int v) {
    buf.addByte(v & 0xFF);
    buf.addByte((v >> 8) & 0xFF);
  }

  /// Nearest-neighbour upscale of [source] into [out], which the caller owns.
  ///
  /// Each source row is expanded once and then copied down, rather than
  /// recomputing a source index per output pixel - at scale 4 that replaces
  /// 128k divisions per frame with a handful of block copies.
  static Uint8List _scaleInto(
    Uint8List out,
    Uint8List source,
    int width,
    int height,
    int scale,
  ) {
    final outWidth = width * scale;
    for (var y = 0; y < height; y++) {
      final srcRow = y * width;
      final rowStart = y * scale * outWidth;
      var o = rowStart;
      for (var x = 0; x < width; x++) {
        final value = source[srcRow + x];
        final end = o + scale;
        while (o < end) {
          out[o++] = value;
        }
      }
      for (var r = 1; r < scale; r++) {
        final at = rowStart + r * outWidth;
        out.setRange(at, at + outWidth, out, rowStart);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // GIF LZW compression
  // ---------------------------------------------------------------------------

  /// Compresses one frame's palette indices into a GIF LZW code stream.
  ///
  /// [table] is scratch space owned by the caller: its contents on entry are
  /// irrelevant and it is left dirty on exit. Zero means "no such entry",
  /// which is unambiguous because assigned codes start at [_firstFreeCode].
  static Uint8List _lzwCompress(Uint8List indices, Int32List table) {
    final writer = _LsbBitWriter();
    table.fillRange(0, table.length, 0);

    var codeSize = _minCodeSize + 1;
    var nextCode = _firstFreeCode;

    writer.write(_clearCode, codeSize);

    if (indices.isNotEmpty) {
      var prefix = indices[0] & _paletteMask;
      for (var i = 1; i < indices.length; i++) {
        final pixel = indices[i] & _paletteMask;
        final key = (prefix << _minCodeSize) | pixel;
        final known = table[key];
        if (known != 0) {
          prefix = known;
          continue;
        }
        writer.write(prefix, codeSize);
        if (nextCode < _maxCode) {
          table[key] = nextCode;
          nextCode++;
          // Widen one code later than this table filling up, because the
          // decoder's table always lags it by a single entry: the decoder adds
          // an entry only once it has read the *following* code, and the code
          // straight after a clear adds nothing at all. Widening when this
          // table fills - the obvious rule - puts every decoder one code out
          // of step and the frame decodes as garbage.
          if (nextCode == (1 << codeSize) + 1) codeSize++;
        } else {
          // Table full. Both sides start over rather than let codes outgrow
          // the 12 bits GIF allows. Like the final data code below, this one
          // is emitted without assigning an entry - it is safe only because
          // the decoder cannot widen past 12 either.
          writer.write(_clearCode, codeSize);
          table.fillRange(0, table.length, 0);
          codeSize = _minCodeSize + 1;
          nextCode = _firstFreeCode;
        }
        prefix = pixel;
      }
      writer.write(prefix, codeSize);
      // The final data code is the only one emitted without assigning a table
      // entry, so it never reaches the widen check above - but the decoder
      // adds an entry for it like any other, and can cross a power of two and
      // widen before it reads the terminator. Without this the end-of-input
      // code is written narrower than the decoder is listening for, and the
      // stream ends with no readable terminator. Pixels still decode, which is
      // why a lenient viewer hides it.
      if (nextCode >= (1 << codeSize) && codeSize < _maxCodeSize) codeSize++;
    }

    writer.write(_eoiCode, codeSize);
    writer.flush();
    return writer.bytes();
  }
}

/// Writes integers LSB-first into a byte buffer (GIF bit packing).
class _LsbBitWriter {
  Uint8List _buf = Uint8List(4096);
  int _length = 0;
  int _bits = 0;
  int _count = 0;

  void _put(int byte) {
    if (_length == _buf.length) {
      final grown = Uint8List(_buf.length * 2);
      grown.setRange(0, _length, _buf);
      _buf = grown;
    }
    _buf[_length++] = byte;
  }

  void write(int value, int numBits) {
    _bits |= value << _count;
    _count += numBits;
    while (_count >= 8) {
      _put(_bits & 0xFF);
      _bits >>= 8;
      _count -= 8;
    }
  }

  void flush() {
    if (_count > 0) {
      _put(_bits & 0xFF);
      _bits = 0;
      _count = 0;
    }
  }

  /// A view, not a copy: the caller consumes it before the next frame runs.
  Uint8List bytes() => Uint8List.sublistView(_buf, 0, _length);
}
