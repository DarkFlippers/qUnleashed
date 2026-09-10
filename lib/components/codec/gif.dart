import 'dart:convert';
import 'dart:typed_data';

/// A rectangle of the frame, in source pixels.
typedef _Rect = ({int left, int top, int width, int height});

/// Pure-Dart GIF89a encoder for 2-color (monochrome) animations.
///
/// Designed for 128×64 Flipper Zero screen recordings.
/// Uses LZW compression with LSB-first bit packing per the GIF89a spec.
///
/// Two colours are drawn, but the palette carries four entries because the
/// format rounds to a power of two. The third is the transparent index; both
/// spares hold the background colour, so a viewer that ignores the
/// transparency flag shows background rather than something arbitrary.
///
/// Frames after the first are written as the rectangle that changed, with
/// pixels that did not change left transparent, so a mostly-static recording
/// costs only what moved. See [_writeFrame] for what that requires of the
/// container.
abstract final class FlipperGifEncoder {
  /// A two-colour palette needs a 2-bit minimum code size, which is also the
  /// smallest the format permits. Fixing it here rather than threading it
  /// around is what lets the code table below be sized to the palette.
  static const int _minCodeSize = 2;
  static const int _clearCode = 1 << _minCodeSize;
  static const int _eoiCode = _clearCode + 1;
  static const int _firstFreeCode = _eoiCode + 1;

  /// Codes are at most 12 bits wide, so [_maxCode] is one past the last of
  /// them.
  static const int _maxCodeSize = 12;
  static const int _maxCode = 1 << _maxCodeSize;

  /// The two drawable entries. Masking a caller's index keeps it clear of
  /// [_transparentIndex]: a stray 2 would be emitted as transparent and let
  /// the previous frame show through instead of being painted over, and a
  /// stray 3 would land on the unused palette slot. Anything from 4 up cannot
  /// reach the code stream in any case - [_lzwCompress] masks to the 2-bit
  /// code space regardless.
  static const int _paletteMask = 1;

  /// A third entry, never drawn: it marks the pixels a frame leaves alone.
  /// A 2-bit code size allows four entries, so this costs no extra width.
  static const int _transparentIndex = 2;

  /// One slot per (prefix, pixel) pair. Keying on the palette width rather
  /// than on a whole byte keeps the table at 64KB instead of 4MB, which is
  /// most of why the encoder is faster than the one that did not compress.
  static const int _tableSlots = _maxCode << _minCodeSize;

  /// Encodes frames into an animated GIF89a byte sequence.
  ///
  /// [frames]   — pixel index arrays, each [width]×[height] long. Values are
  ///              expected to be 0 or 1; anything else is folded into the
  ///              palette rather than rejected.
  /// [delaysMs] — per-frame delay in milliseconds.
  /// [color0]   — background color as 0xAARRGGBB.
  /// [color1]   — foreground color as 0xAARRGGBB.
  /// [scale]    — integer nearest-neighbour upscale of the whole animation.
  ///
  /// Throws [ArgumentError] rather than asserting. These used to be asserts,
  /// which are stripped in release - so in a release build a bad size wrote a
  /// file some viewers reject and others render wrong, and a short [delaysMs]
  /// threw a RangeError from deep in the loop instead.
  static Uint8List encode({
    required int width,
    required int height,
    required List<Uint8List> frames,
    required List<int> delaysMs,
    required int color0,
    required int color1,
    int scale = 1,
  }) {
    final outputWidth = width * scale;
    final outputHeight = height * scale;
    _validate(
      width,
      height,
      outputWidth,
      outputHeight,
      frames,
      delaysMs,
      scale,
    );

    final buf = BytesBuilder();
    _writeHeader(buf, outputWidth, outputHeight, color0, color1);

    // Allocated once and reused across frames.
    final table = Int32List(_tableSlots);
    final previous = Uint8List(width * height);
    final current = Uint8List(width * height);
    final region = Uint8List(outputWidth * outputHeight);

    for (var i = 0; i < frames.length; i++) {
      current.setAll(0, frames[i]);

      // The first frame has nothing underneath it, so it is written whole and
      // opaque; every later one is only what moved.
      final rect = i == 0
          ? (left: 0, top: 0, width: width, height: height)
          : _changedRect(current, previous, width, height);

      _writeFrame(
        buf,
        delaysMs[i],
        _fillRegion(region, current, previous, rect, width, scale, i != 0),
        rect,
        scale,
        transparent: i != 0,
        table: table,
      );

      previous.setAll(0, current);
    }

    buf.addByte(0x3B); // GIF trailer
    return buf.toBytes();
  }

  /// Refuses what cannot be encoded, rather than writing a file that some
  /// viewers reject and others render wrong.
  ///
  /// The scaled size matters as much as the declared one: every dimension in
  /// the format is 16 bits, so a larger one is truncated by [_le16] into a
  /// file that declares a smaller image than it carries and decodes without
  /// complaint. Neither caller can reach that, but this is a shared component
  /// and the next one has nothing else stopping it.
  static void _validate(
    int width,
    int height,
    int outputWidth,
    int outputHeight,
    List<Uint8List> frames,
    List<int> delaysMs,
    int scale,
  ) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame size must be positive, got ${width}x$height.');
    }
    if (scale < 1) {
      throw ArgumentError.value(scale, 'scale', 'Must be at least 1.');
    }
    if (outputWidth > 0xFFFF || outputHeight > 0xFFFF) {
      throw ArgumentError(
        'Scaled size must fit 16 bits, got ${outputWidth}x$outputHeight.',
      );
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
  }

  /// The logical screen descriptor, the shared palette and the loop block -
  /// everything written once, before any frame.
  static void _writeHeader(
    BytesBuilder buf,
    int outputWidth,
    int outputHeight,
    int color0,
    int color1,
  ) {
    buf.add(ascii.encode('GIF89a'));
    _le16(buf, outputWidth);
    _le16(buf, outputHeight);
    // A global colour table, because every frame uses the same one. A local
    // table repeats the same 12 bytes on every frame, which a diffed still
    // frame - a couple of dozen bytes in total - cannot afford.
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
  }

  /// The smallest rectangle covering every pixel that differs from [previous].
  ///
  /// Compared at source resolution: a scaled pixel changes exactly when its
  /// source pixel does, so diffing after scaling would examine scale-squared
  /// as many bytes for the same answer.
  ///
  /// A frame identical to the one before it has no such rectangle; a 1×1 one
  /// is returned instead, which combined with transparency draws nothing and
  /// costs a handful of bytes. Returning the whole frame would cost everything.
  static _Rect _changedRect(
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
  /// expanded once and copied down, so an unchanged region outside the
  /// rectangle is never touched at all. The palette mask is applied here too,
  /// for the same reason - this is the one place a pixel value is written, so
  /// a pass over every frame to mask them cost a quarter of the encode for
  /// nothing.
  ///
  /// The result aliases [out] and is only valid until the next frame reuses
  /// it.
  static Uint8List _fillRegion(
    Uint8List out,
    Uint8List current,
    Uint8List previous,
    _Rect rect,
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
            : current[s] & _paletteMask;
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

  /// Four entries: the two drawable colours, then padding to the power of two
  /// the format requires. Both spares hold the background colour, so index 3 -
  /// which nothing ever references - and the transparent index alike read as
  /// background to a viewer that ignores transparency.
  static void _writePalette(BytesBuilder buf, int color0, int color1) {
    for (final color in [color0, color1, color0, color0]) {
      buf.addByte((color >> 16) & 0xFF);
      buf.addByte((color >> 8) & 0xFF);
      buf.addByte(color & 0xFF);
    }
  }

  /// Writes one image block.
  ///
  /// Two container details make the sub-rectangles work. The disposal method
  /// is "do not dispose", so each frame stays on screen as the ground for the
  /// next; and the transparent flag lets the untouched pixels inside a
  /// rectangle fall through to it. Without either, a partial frame would show
  /// as a fragment on an empty canvas.
  static void _writeFrame(
    BytesBuilder buf,
    int delayMs,
    Uint8List indices,
    _Rect rect,
    int scale, {
    required bool transparent,
    required Int32List table,
  }) {
    // GIF delay is in centiseconds (1/100 s). Zero is legal but makes viewers
    // substitute a rate of their own, so the floor is one.
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
    _le16(buf, rect.left * scale);
    _le16(buf, rect.top * scale);
    _le16(buf, rect.width * scale);
    _le16(buf, rect.height * scale);
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
      // The final data code assigns no table entry, so it never reaches the
      // widen check above - the same is true of the code before a reset - but
      // the decoder
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

  /// A view into the buffer, not a copy: any later write may reallocate and
  /// leave it stale.
  Uint8List bytes() => Uint8List.sublistView(_buf, 0, _length);
}
