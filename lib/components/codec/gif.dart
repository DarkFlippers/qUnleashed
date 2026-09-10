import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart GIF89a encoder for 2-color (monochrome) animations.
///
/// Designed for 128×64 Flipper Zero screen recordings.
/// Uses LZW compression with LSB-first bit packing per the GIF89a spec.
///
/// Frames after the first are written as the rectangle that changed, with
/// pixels that did not change left transparent, so a mostly-static recording
/// costs only what moved. See [_writeFrame] for what that requires of the
/// container.
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

  /// The two drawable entries. Masking a caller's index to them keeps a stray
  /// value out of the code stream, where it would not be a wrong colour but a
  /// structural break: index 4 is the clear code and index 5 is end-of-input,
  /// either of which derails a decoder mid-frame.
  static const int _paletteMask = 1;

  /// A third entry, never drawn: it marks the pixels a frame leaves alone.
  /// A 2-bit code size allows four entries, so this costs no extra width.
  static const int _transparentIndex = 2;

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
  ///
  /// Throws [ArgumentError] rather than asserting: every one of these produces
  /// a file that some viewers reject and others render wrong, and an assert
  /// would let exactly that ship in a release build.
  static Uint8List encode({
    required int width,
    required int height,
    required List<Uint8List> frames,
    required List<int> delaysMs,
    required int color0,
    required int color1,
    int scale = 1,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame size must be positive, got ${width}x$height.');
    }
    if (scale < 1) {
      throw ArgumentError.value(scale, 'scale', 'Must be at least 1.');
    }
    if (frames.isEmpty) {
      throw ArgumentError.value(frames, 'frames', 'At least one is required.');
    }
    if (delaysMs.length != frames.length) {
      throw ArgumentError.value(
        delaysMs.length,
        'delaysMs.length',
        'Must match frames.length (${frames.length}).',
      );
    }
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].length != width * height) {
        throw ArgumentError.value(
          frames[i].length,
          'frames[$i].length',
          'Must be ${width * height} for a ${width}x$height frame.',
        );
      }
    }

    final buf = BytesBuilder();
    final outputWidth = width * scale;
    final outputHeight = height * scale;

    // GIF89a header
    buf.add(ascii.encode('GIF89a'));
    _le16(buf, outputWidth);
    _le16(buf, outputHeight);
    // A global colour table, because every frame uses the same one: with
    // per-frame tables the palette was re-stated identically for each, which
    // on a still recording is a third of what the frame costs.
    // Packed: table present, size=1 -> 2^(1+1) = 4 entries.
    buf.addByte(0x81);
    buf.addByte(0x00); // background color index
    buf.addByte(0x00); // pixel aspect ratio
    _writePalette(buf, color0, color1);

    // Netscape Application Extension — infinite loop
    buf.addByte(0x21);
    buf.addByte(0xFF);
    buf.addByte(11);
    buf.add(ascii.encode('NETSCAPE2.0'));
    buf.addByte(3); // sub-block size
    buf.addByte(1); // sub-block ID
    _le16(buf, 0); // loop count 0 = infinite
    buf.addByte(0); // block terminator

    // Allocated once and reused. The diff runs at source resolution because a
    // scaled pixel changes exactly when its source pixel does, so scaling
    // first would compare up to sixteen times as many bytes for the same
    // answer.
    final table = Int32List(_tableSlots);
    final previous = Uint8List(width * height);
    final current = Uint8List(width * height);
    final region = Uint8List(outputWidth * outputHeight);

    for (var i = 0; i < frames.length; i++) {
      final source = frames[i];
      for (var p = 0; p < current.length; p++) {
        current[p] = source[p] & _paletteMask;
      }

      // The first frame has nothing underneath it, so it is written whole and
      // opaque; every later one is only what moved.
      final rect = i == 0
          ? (left: 0, top: 0, width: width, height: height)
          : _changedRect(current, previous, width, height);

      _writeFrame(
        buf,
        delaysMs[i],
        _fillRegion(region, current, previous, rect, width, scale, i != 0),
        rect.width * scale,
        rect.height * scale,
        rect.left * scale,
        rect.top * scale,
        transparent: i != 0,
        table: table,
      );

      previous.setAll(0, current);
    }

    buf.addByte(0x3B); // GIF trailer
    return buf.toBytes();
  }

  /// The smallest rectangle covering every pixel that differs from [previous].
  ///
  /// A frame identical to the one before it has no such rectangle; a 1×1 one
  /// is returned instead, which combined with transparency draws nothing and
  /// costs a handful of bytes. Returning the whole frame would cost everything.
  static ({int left, int top, int width, int height}) _changedRect(
    Uint8List current,
    Uint8List previous,
    int width,
    int height,
  ) {
    var minX = width, minY = height, maxX = -1, maxY = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (current[row + x] == previous[row + x]) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        maxY = y;
      }
    }
    if (maxY < 0) return (left: 0, top: 0, width: 1, height: 1);
    return (
      left: minX,
      top: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  /// Fills [out] with the scaled pixels of [rect], marking anything unchanged
  /// as transparent when [diff] is set.
  ///
  /// Scaling happens here rather than over the whole frame: each source row is
  /// expanded once and copied down, so an unchanged region is never touched at
  /// all.
  static Uint8List _fillRegion(
    Uint8List out,
    Uint8List current,
    Uint8List previous,
    ({int left, int top, int width, int height}) rect,
    int sourceWidth,
    int scale,
    bool diff,
  ) {
    final outWidth = rect.width * scale;
    for (var ry = 0; ry < rect.height; ry++) {
      final srcRow = (rect.top + ry) * sourceWidth + rect.left;
      final rowStart = ry * scale * outWidth;
      var o = rowStart;
      for (var rx = 0; rx < rect.width; rx++) {
        final s = srcRow + rx;
        final value = diff && current[s] == previous[s]
            ? _transparentIndex
            : current[s];
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
    return Uint8List.sublistView(out, 0, outWidth * rect.height * scale);
  }

  /// Writes one image block.
  ///
  /// Two container details make the sub-rectangles work. The disposal method
  /// is "do not dispose", so each frame stays on screen as the ground for the
  /// next; and the transparent flag lets the untouched pixels inside a
  /// rectangle fall through to it. Without either, a partial frame would show
  /// as a fragment on an empty canvas.
  /// Four entries: the two drawable colours, then padding to the power of two
  /// the format requires. The spare entries are never referenced except by the
  /// transparent index, which is never drawn.
  static void _writePalette(BytesBuilder buf, int color0, int color1) {
    for (final color in [color0, color1, color0, color0]) {
      buf.addByte((color >> 16) & 0xFF);
      buf.addByte((color >> 8) & 0xFF);
      buf.addByte(color & 0xFF);
    }
  }

  static void _writeFrame(
    BytesBuilder buf,
    int delayMs,
    Uint8List indices,
    int pixelWidth,
    int pixelHeight,
    int left,
    int top, {
    required bool transparent,
    required Int32List table,
  }) {
    // GIF delay is in centiseconds (1/100 s); clamp to valid range.
    final cs = (delayMs / 10).round().clamp(1, 65535);

    // Graphic Control Extension
    buf.addByte(0x21);
    buf.addByte(0xF9);
    buf.addByte(0x04); // block size
    buf.addByte(transparent ? 0x05 : 0x04); // dispose=1, transparent flag
    _le16(buf, cs);
    buf.addByte(transparent ? _transparentIndex : 0x00);
    buf.addByte(0x00); // block terminator

    // Image Descriptor
    buf.addByte(0x2C); // image separator
    _le16(buf, left);
    _le16(buf, top);
    _le16(buf, pixelWidth);
    _le16(buf, pixelHeight);
    // Packed byte: no local colour table, no interlace - the global one above
    // serves every frame.
    buf.addByte(0x00);

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
      // Masked to the code space, not the palette: the transparent index is a
      // legitimate value here and must survive.
      var prefix = indices[0] & (_clearCode - 1);
      for (var i = 1; i < indices.length; i++) {
        final pixel = indices[i] & (_clearCode - 1);
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
