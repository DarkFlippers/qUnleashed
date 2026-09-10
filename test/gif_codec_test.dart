import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/codec/gif.dart';

/// One decoded frame: palette indices at the GIF's own resolution.
typedef DecodedFrame = ({
  int width,
  int height,
  int delayCs,
  int gcePacked,
  Uint8List palette,
  Uint8List pixels,
  Uint8List payload,
  int clearCodes,
});

/// A GIF89a reader written from the specification rather than from the
/// encoder, so a mistake shared by both is not silently agreed upon. The
/// encoder's output was separately checked against an outside decoder; this is
/// what keeps that check from having to be repeated by hand on every change.
List<DecodedFrame> decodeGif(Uint8List bytes) {
  var p = 0;
  int u8() => bytes[p++];
  int u16() {
    final v = bytes[p] | (bytes[p + 1] << 8);
    p += 2;
    return v;
  }

  expect(String.fromCharCodes(bytes.sublist(0, 6)), 'GIF89a');
  p = 6;
  u16();
  u16();
  final screenPacked = u8();
  expect(screenPacked & 0x80, 0, reason: 'no global colour table is written');
  u8();
  u8();

  final frames = <DecodedFrame>[];
  var pendingDelay = 0;
  var pendingPacked = 0;

  while (true) {
    final block = u8();
    if (block == 0x3B) break;

    if (block == 0x21) {
      final label = u8();
      if (label == 0xF9) {
        expect(u8(), 4, reason: 'graphic control block size');
        pendingPacked = u8();
        pendingDelay = u16();
        u8();
        expect(u8(), 0, reason: 'graphic control terminator');
      } else {
        final size = u8();
        p += size;
        while (bytes[p] != 0) {
          p += bytes[p] + 1;
        }
        p++;
      }
      continue;
    }

    expect(block, 0x2C, reason: 'image separator');
    u16();
    u16();
    final w = u16();
    final h = u16();
    final packed = u8();
    expect(packed & 0x80, 0x80, reason: 'local colour table present');
    // Read rather than skipped: a palette written in the wrong order or the
    // wrong channel order ships a visibly wrong GIF that decodes perfectly.
    final tableBytes = (1 << ((packed & 0x07) + 1)) * 3;
    final palette = Uint8List.fromList(bytes.sublist(p, p + tableBytes));
    p += tableBytes;

    final minCodeSize = u8();
    final data = <int>[];
    while (true) {
      final size = u8();
      if (size == 0) break;
      data.addAll(bytes.sublist(p, p + size));
      p += size;
    }

    final payload = Uint8List.fromList(data);
    final clears = _clearCodeCount(payload, minCodeSize);
    frames.add((
      width: w,
      height: h,
      delayCs: pendingDelay,
      gcePacked: pendingPacked,
      palette: palette,
      pixels: _lzwDecode(payload, minCodeSize, w * h),
      payload: payload,
      clearCodes: clears,
    ));
  }
  return frames;
}

Uint8List _lzwDecode(Uint8List data, int minCodeSize, int expected) {
  final clear = 1 << minCodeSize;
  final eoi = clear + 1;

  var codeSize = minCodeSize + 1;
  var next = clear + 2;
  var dict = <List<int>>[
    for (var i = 0; i < clear; i++) [i],
    <int>[],
    <int>[],
  ];

  final out = <int>[];
  var bitPos = 0;
  var readAny = false;
  var sawEnd = false;
  List<int>? prev;

  int? readCode() {
    if ((bitPos + codeSize) > data.length * 8) return null;
    var value = 0;
    for (var i = 0; i < codeSize; i++) {
      final bit = (data[(bitPos + i) >> 3] >> ((bitPos + i) & 7)) & 1;
      value |= bit << i;
    }
    bitPos += codeSize;
    return value;
  }

  while (true) {
    final code = readCode();
    if (code == null) break;
    if (code == eoi) {
      sawEnd = true;
      break;
    }
    if (!readAny) {
      // The spec has the stream open with a clear code, and decoders rely on
      // it to size their table before the first data code arrives.
      expect(code, clear, reason: 'stream must open with a clear code');
      readAny = true;
    }
    if (code == clear) {
      codeSize = minCodeSize + 1;
      next = clear + 2;
      dict = <List<int>>[
        for (var i = 0; i < clear; i++) [i],
        <int>[],
        <int>[],
      ];
      prev = null;
      continue;
    }

    final List<int> entry;
    if (code < dict.length) {
      entry = dict[code];
    } else {
      expect(prev, isNotNull, reason: 'undefined code with no prefix');
      entry = [...prev!, prev[0]];
    }
    out.addAll(entry);

    if (prev != null && next < 4096) {
      dict.add([...prev, entry[0]]);
      next++;
      if (next == (1 << codeSize) && codeSize < 12) codeSize++;
    }
    prev = entry;
  }

  // Running out of bits is not the same as being told the stream ended, and
  // conflating them is how a terminator written at the wrong width goes
  // unnoticed: the pixels still decode, so only this notices.
  expect(sawEnd, isTrue, reason: 'stream must end with an end-of-input code');
  expect(
    data.length * 8 - bitPos,
    lessThan(8),
    reason: 'only padding may follow the terminator',
  );
  expect(out.length, expected, reason: 'decoded pixel count');
  return Uint8List.fromList(out);
}

/// How many clear codes the stream carries. One is the mandatory opener, so
/// more than one means the code table filled and was reset mid-frame - which
/// is the only way to know a test meant to exercise that branch reached it.
int _clearCodeCount(Uint8List data, int minCodeSize) {
  final clear = 1 << minCodeSize;
  final eoi = clear + 1;
  var codeSize = minCodeSize + 1;
  var next = clear + 2;
  var bitPos = 0;
  var count = 0;
  var entries = 0;
  while (bitPos + codeSize <= data.length * 8) {
    var code = 0;
    for (var i = 0; i < codeSize; i++) {
      code |= ((data[(bitPos + i) >> 3] >> ((bitPos + i) & 7)) & 1) << i;
    }
    bitPos += codeSize;
    if (code == eoi) break;
    if (code == clear) {
      count++;
      codeSize = minCodeSize + 1;
      next = clear + 2;
      entries = 0;
      continue;
    }
    if (entries > 0 && next < 4096) {
      next++;
      if (next == (1 << codeSize) && codeSize < 12) codeSize++;
    }
    entries++;
  }
  return count;
}

Uint8List solid(int n, int v) => Uint8List(n)..fillRange(0, n, v);

Uint8List stripes(int w, int h) => Uint8List.fromList([
  for (var y = 0; y < h; y++)
    for (var x = 0; x < w; x++) (x ~/ 3 + y ~/ 5) % 2,
]);

Uint8List noise(int n, int seed) {
  final rnd = Random(seed);
  return Uint8List.fromList([for (var i = 0; i < n; i++) rnd.nextInt(2)]);
}

Uint8List encode(
  List<Uint8List> frames, {
  int width = 128,
  int height = 64,
  int scale = 1,
  List<int>? delaysMs,
}) => FlipperGifEncoder.encode(
  width: width,
  height: height,
  frames: frames,
  delaysMs: delaysMs ?? List<int>.filled(frames.length, 100),
  color0: 0xFF000000,
  color1: 0xFFFFFFFF,
  scale: scale,
);

Uint8List scaledUp(Uint8List src, int w, int h, int scale) {
  final out = Uint8List(w * scale * h * scale);
  for (var y = 0; y < h * scale; y++) {
    for (var x = 0; x < w * scale; x++) {
      out[y * w * scale + x] = src[(y ~/ scale) * w + (x ~/ scale)];
    }
  }
  return out;
}

int indexOfSequence(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

void main() {
  group('round trip', () {
    void roundTrip(String what, List<Uint8List> frames, {int scale = 1}) {
      test(what, () {
        final decoded = decodeGif(encode(frames, scale: scale));

        expect(decoded.length, frames.length);
        for (var i = 0; i < frames.length; i++) {
          expect(decoded[i].width, 128 * scale);
          expect(decoded[i].height, 64 * scale);
          expect(
            decoded[i].pixels,
            scaledUp(frames[i], 128, 64, scale),
            reason: 'frame $i',
          );
        }
      });
    }

    roundTrip('a frame of only background', [solid(8192, 0)]);
    roundTrip('a frame of only foreground', [solid(8192, 1)]);
    roundTrip('a frame with structure', [stripes(128, 64)]);
    roundTrip('several frames', [
      solid(8192, 0),
      stripes(128, 64),
      noise(8192, 7),
      solid(8192, 1),
    ]);
    roundTrip('a scaled frame', [stripes(128, 64)], scale: 2);

    // Noise at scale 4 is 128k pixels of incompressible data, which is the
    // only way to fill the 4096-code table and take the reset branch.
    roundTrip('enough data to fill and reset the code table', [
      noise(8192, 11),
    ], scale: 4);

    test('that reset case really does reset', () {
      // Otherwise a changed seed, scale or SDK Random leaves the test passing
      // while covering nothing. One clear code is the mandatory opener.
      final decoded = decodeGif(encode([noise(8192, 11)], scale: 4));

      expect(decoded.single.clearCodes, greaterThanOrEqualTo(2));
    });

    test('a frame that does not fill the table needs only its opener', () {
      expect(decodeGif(encode([solid(8192, 0)])).single.clearCodes, 1);
    });

    // The scale buffer is allocated once and reused across frames, so a frame
    // that failed to overwrite every pixel would show the previous one's
    // content. Single-frame scale tests cannot see that.
    test('scaled frames do not bleed into one another', () {
      final frames = [solid(8192, 1), solid(8192, 0), stripes(128, 64)];

      final decoded = decodeGif(encode(frames, scale: 2));

      for (var i = 0; i < frames.length; i++) {
        expect(
          decoded[i].pixels,
          scaledUp(frames[i], 128, 64, 2),
          reason: 'frame $i',
        );
      }
    });

    test('a single pixel', () {
      final decoded = decodeGif(encode([solid(1, 1)], width: 1, height: 1));
      expect(decoded.single.pixels, Uint8List.fromList([1]));
    });

    // Three data codes is where the decoder widens immediately before reading
    // the terminator, and the stream happens to be byte-aligned - so there is
    // no spare padding bit to disguise a terminator written too narrow.
    test('a frame whose last code lands on a width boundary', () {
      final decoded = decodeGif(encode([solid(64, 0)], width: 8, height: 8));

      expect(decoded.single.pixels, solid(64, 0));
    });

    // An index outside the two-colour palette is a caller bug, but it must not
    // become a structural break: index 4 is the clear code and 5 is
    // end-of-input, either of which derails a decoder mid-frame.
    test('folds a stray index into the two-colour palette', () {
      final input = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 255, 1, 0]);

      final decoded = decodeGif(encode([input], width: 4, height: 3));

      expect(
        decoded.single.pixels,
        Uint8List.fromList([for (final v in input) v & 1]),
      );
    });

    test('a size that leaves a partial byte in the bit stream', () {
      final pixels = noise(21, 3);
      final decoded = decodeGif(encode([pixels], width: 7, height: 3));
      expect(decoded.single.pixels, pixels);
    });
  });

  group('encoded structure', () {
    // Nothing about the pixel stream changes if the palette is written wrong,
    // so a swapped or byte-reversed table ships a visibly inverted GIF that
    // decodes perfectly. Both callers pass asymmetric colours.
    test('writes the colour table as RGB, background entry first', () {
      final decoded = decodeGif(
        FlipperGifEncoder.encode(
          width: 8,
          height: 8,
          frames: [solid(64, 0)],
          delaysMs: [100],
          color0: 0xFF102030,
          color1: 0xFF405060,
        ),
      );

      expect(decoded.single.palette, [0x10, 0x20, 0x30, 0x40, 0x50, 0x60]);
    });

    test('disposes nothing and declares no transparent index', () {
      // Frames are full-screen and opaque, so every pixel is replaced. If that
      // ever stops being true, these flags have to move with it.
      expect(decodeGif(encode([solid(8192, 0)])).single.gcePacked, 0x00);
    });

    test('rounds a delay rather than truncating it', () {
      // 105ms is 10.5 centiseconds. A multiple of ten cannot tell the two
      // apart, which is why every earlier delay case here was one.
      expect(
        decodeGif(encode([solid(8192, 0)], delaysMs: [105])).single.delayCs,
        11,
      );
    });

    test('carries the per-frame delay in centiseconds', () {
      final decoded = decodeGif(
        encode([solid(8192, 0), solid(8192, 1)], delaysMs: [40, 250]),
      );

      expect(decoded.map((f) => f.delayCs), [4, 25]);
    });

    test('clamps a delay too small for the format', () {
      expect(
        decodeGif(encode([solid(8192, 0)], delaysMs: [1])).single.delayCs,
        1,
        reason: 'zero would make viewers substitute their own rate',
      );
    });

    // A round trip constrains the encoder and decoder as a *pair*, and one
    // wrong-but-consistent pair survives it: widening when the encoder's table
    // fills, with a decoder that widens a step early. That is the rule a
    // future reader is most likely to reach for, and real decoders reject it.
    // Pinning the bytes removes the freedom to move both sides together.
    test('produces exactly these codes for a known input', () {
      final pixels = Uint8List.fromList([
        for (var i = 0; i < 64; i++) (i ~/ 3) % 2,
      ]);

      final decoded = decodeGif(encode([pixels], width: 8, height: 8));

      expect(decoded.single.payload, [
        132,
        131,
        6,
        24,
        202,
        158,
        78,
        92,
        243,
        201,
        118,
        33,
        94,
        5,
      ]);
    });

    test('ends with the trailer', () {
      expect(encode([stripes(128, 64)]).last, 0x3B);
    });

    test('loops forever', () {
      final bytes = encode([solid(8192, 0)]);
      final marker = 'NETSCAPE2.0'.codeUnits;
      final at = indexOfSequence(bytes, marker);

      expect(at, greaterThan(0), reason: 'application extension present');
      expect(bytes.sublist(at + marker.length, at + marker.length + 5), [
        3,
        1,
        0,
        0,
        0,
      ]);
    });
  });

  group('compression', () {
    // The guard against what was here before: a clear code before every pair of
    // pixels, spending 4.5 bits on each bit of input. Anything that stops
    // compressing lands far above these bounds.
    test('a flat frame costs a few hundred bytes, not kilobytes', () {
      expect(encode([solid(8192, 0)]).length, lessThan(200));
    });

    test('a screen-like frame stays well under one bit per pixel', () {
      expect(encode([stripes(128, 64)]).length * 8 / 8192, lessThan(0.45));
    });

    test('scaling up costs far less than the pixels it adds', () {
      final one = encode([stripes(128, 64)]).length;
      final four = encode([stripes(128, 64)], scale: 4).length;

      // 16x the pixels, but the runs get 4x longer in both directions, so it
      // measures around 8.5x. The ratio alone cannot see a regression that
      // inflates both sides equally, so the absolute size is bounded too.
      expect(four, lessThan(one * 12));
      expect(four, lessThan(4000));
    });

    test('incompressible input does not run away', () {
      // Noise cannot compress, but it must not expand the way the literal
      // stream did, which cost 4.5 bits for every one bit of input.
      expect(encode([noise(8192, 5)]).length * 8 / 8192, lessThan(1.5));
    });
  });
}
