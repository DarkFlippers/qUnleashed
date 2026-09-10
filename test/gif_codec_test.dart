import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/codec/gif.dart';

/// One decoded frame: palette indices at the GIF's own resolution.
typedef DecodedFrame = ({int width, int height, int delayCs, Uint8List pixels});

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

  while (true) {
    final block = u8();
    if (block == 0x3B) break;

    if (block == 0x21) {
      final label = u8();
      if (label == 0xF9) {
        expect(u8(), 4, reason: 'graphic control block size');
        u8();
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
    p += (1 << ((packed & 0x07) + 1)) * 3;

    final minCodeSize = u8();
    final data = <int>[];
    while (true) {
      final size = u8();
      if (size == 0) break;
      expect(size, lessThanOrEqualTo(255));
      data.addAll(bytes.sublist(p, p + size));
      p += size;
    }

    frames.add((
      width: w,
      height: h,
      delayCs: pendingDelay,
      pixels: _lzwDecode(Uint8List.fromList(data), minCodeSize, w * h),
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
    if (code == null || code == eoi) break;
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

  expect(out.length, expected, reason: 'decoded pixel count');
  return Uint8List.fromList(out);
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

    test('a single pixel', () {
      final decoded = decodeGif(encode([solid(1, 1)], width: 1, height: 1));
      expect(decoded.single.pixels, Uint8List.fromList([1]));
    });

    test('a size that leaves a partial byte in the bit stream', () {
      final pixels = noise(21, 3);
      final decoded = decodeGif(encode([pixels], width: 7, height: 3));
      expect(decoded.single.pixels, pixels);
    });
  });

  group('encoded structure', () {
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
      expect(encode([solid(8192, 0)]).length, lessThan(400));
    });

    test('a screen-like frame stays well under one bit per pixel', () {
      expect(encode([stripes(128, 64)]).length * 8 / 8192, lessThan(1.0));
    });

    test('scaling up costs far less than the pixels it adds', () {
      final one = encode([stripes(128, 64)]).length;
      final four = encode([stripes(128, 64)], scale: 4).length;

      // 16x the pixels, but the runs get 4x longer in both directions, so it
      // measures around 8.5x. The bound is what proves the cost is sublinear
      // without pinning the exact ratio.
      expect(four, lessThan(one * 12));
    });

    test('incompressible input does not run away', () {
      // Noise cannot compress, but it must not expand the way the literal
      // stream did, which cost 4.5 bits for every one bit of input.
      expect(encode([noise(8192, 5)]).length * 8 / 8192, lessThan(2.0));
    });
  });
}
