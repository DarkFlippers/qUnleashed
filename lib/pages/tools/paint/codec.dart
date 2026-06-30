import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../theme/colors/display.dart';
import 'constants.dart';

abstract final class PaintCodec {
  static Uint8List encodeXBM(Uint8List pixels) {
    final data = Uint8List(1024);
    for (int y = 0; y < kCanvasHeight; y++) {
      for (int x = 0; x < kCanvasWidth; x++) {
        if (pixels[y * kCanvasWidth + x] != 0) {
          data[y * 16 + (x ~/ 8)] |= (1 << (x & 7));
        }
      }
    }
    return data;
  }

  /// Unpacks a 1bpp XBM buffer into the fixed [kCanvasWidth]×[kCanvasHeight]
  /// pixel grid, bottom-aligned. The source may be shorter than the canvas
  /// (e.g. Flipper animations are 128 wide but often 54 tall); the blank
  /// padding then sits at the top, matching how the device draws them.
  /// [srcWidth] sets the row stride so frames narrower than 128px unpack
  /// correctly.
  static Uint8List xbmToPixels(
    Uint8List xbm, {
    int srcWidth = kCanvasWidth,
    int srcHeight = kCanvasHeight,
  }) {
    final pixels = Uint8List(kCanvasWidth * kCanvasHeight);
    final rowBytes = (srcWidth + 7) >> 3;
    final w = math.min(srcWidth, kCanvasWidth);
    final h = math.min(srcHeight, kCanvasHeight);
    final offY = kCanvasHeight - h;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final byteIdx = y * rowBytes + (x >> 3);
        if (byteIdx < xbm.length && (xbm[byteIdx] & (1 << (x & 7))) != 0) {
          pixels[(y + offY) * kCanvasWidth + x] = 1;
        }
      }
    }
    return pixels;
  }

  static Uint8List? decodeBmFile(Uint8List data) {
    if (data.isEmpty) return null;
    if (data[0] == 0x01) {
      if (data.length < 4) return null;
      final compLen = data[2] | (data[3] << 8);
      if (data.length < 4 + compLen) return null;
      return heatshrinkDecode(data.sublist(4, 4 + compLen));
    }
    return data.length > 1 ? data.sublist(1) : null;
  }

  static Uint8List encodeBmUncompressed(Uint8List xbm) {
    final out = Uint8List(1 + xbm.length);
    out[0] = 0x00;
    out.setRange(1, out.length, xbm);
    return out;
  }

  static Uint8List encodeBmCompressed(Uint8List xbm) {
    final compressed = heatshrinkEncode(xbm);
    final out = Uint8List(4 + compressed.length);
    out[0] = 0x01;
    out[1] = 0x00;
    out[2] = compressed.length & 0xFF;
    out[3] = (compressed.length >> 8) & 0xFF;
    out.setRange(4, out.length, compressed);
    return out;
  }

  static Uint8List heatshrinkDecode(Uint8List data) {
    const windowMask = 0xFF;
    final window = Uint8List(256);
    int headIndex = 0;
    final out = <int>[];
    int bytePos = 0;
    int bitIdx = 0;
    int curByte = 0;

    int getBits(int count) {
      int acc = 0;
      for (int i = 0; i < count; i++) {
        if (bitIdx == 0) {
          if (bytePos >= data.length) return -1;
          curByte = data[bytePos++];
          bitIdx = 0x80;
        }
        acc <<= 1;
        if ((curByte & bitIdx) != 0) acc |= 1;
        bitIdx >>= 1;
      }
      return acc;
    }

    int state = 0;
    int bkIdx = 0;
    int bkCnt = 0;

    loop:
    while (true) {
      switch (state) {
        case 0:
          final tag = getBits(1);
          if (tag < 0) break loop;
          if (tag == 1) {
            state = 1;
          } else {
            bkIdx = 0;
            state = 3;
          }
        case 1:
          final b = getBits(8);
          if (b < 0) break loop;
          out.add(b);
          window[headIndex & windowMask] = b;
          headIndex++;
          state = 0;
        case 3:
          final idx = getBits(8);
          if (idx < 0) break loop;
          bkIdx = idx + 1;
          bkCnt = 0;
          state = 5;
        case 5:
          final cnt = getBits(4);
          if (cnt < 0) break loop;
          bkCnt = cnt + 1;
          state = 6;
        case 6:
          for (int i = 0; i < bkCnt; i++) {
            final c = window[(headIndex - bkIdx) & windowMask];
            out.add(c);
            window[headIndex & windowMask] = c;
            headIndex++;
          }
          state = 0;
        default:
          break loop;
      }
    }
    return Uint8List.fromList(out);
  }

  static Uint8List heatshrinkEncode(Uint8List data) {
    final out = <int>[];
    int bitBuf = 0;
    int bitCount = 0;

    void emitBit(int bit) {
      bitBuf = (bitBuf << 1) | (bit & 1);
      if (++bitCount == 8) {
        out.add(bitBuf);
        bitBuf = 0;
        bitCount = 0;
      }
    }

    void emitBits(int val, int count) {
      for (int i = count - 1; i >= 0; i--) {
        emitBit((val >> i) & 1);
      }
    }

    for (int i = 0; i < data.length;) {
      final winStart = (i - 256).clamp(0, i);
      int bestLen = 0;
      int bestOff = 0;
      for (int j = winStart; j < i; j++) {
        int len = 0;
        while (len < 16 && i + len < data.length && data[j + len] == data[i + len]) {
          len++;
        }
        if (len > bestLen) {
          bestLen = len;
          bestOff = i - j;
        }
      }
      if (bestLen >= 2) {
        emitBit(0);
        emitBits(bestOff - 1, 8);
        emitBits(bestLen - 1, 4);
        i += bestLen;
      } else {
        emitBit(1);
        emitBits(data[i], 8);
        i++;
      }
    }

    if (bitCount > 0) out.add(bitBuf << (8 - bitCount));
    return Uint8List.fromList(out);
  }

  static void rgbaToPixels(Uint8List rgba, Uint8List dst) {
    for (int i = 0; i < dst.length; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
      dst[i] = lum < 128 ? 1 : 0;
    }
  }

  static int? parseDolphinInt(String text, String key) {
    final m = RegExp('^$key: (\\d+)\$', multiLine: true).firstMatch(text);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  /// Decodes a 128×64 monochrome pixel buffer into a [ui.Image] suitable for
  /// direct rendering (e.g. animated previews). [fg]/[bg] are ARGB colors used
  /// for set/clear pixels respectively.
  static Future<ui.Image> frameToImage(
    Uint8List pixels, {
    int? fg,
    int? bg,
  }) async {
    final display = DisplayColors.current;
    final fgColor = fg ?? display.foreground.toARGB32();
    final bgColor = bg ?? display.background.toARGB32();
    final rgba = Uint8List(kCanvasWidth * kCanvasHeight * 4);
    for (int i = 0; i < kCanvasWidth * kCanvasHeight; i++) {
      final c = pixels[i] != 0 ? fgColor : bgColor;
      rgba[i * 4] = (c >> 16) & 0xFF;
      rgba[i * 4 + 1] = (c >> 8) & 0xFF;
      rgba[i * 4 + 2] = c & 0xFF;
      rgba[i * 4 + 3] = (c >> 24) & 0xFF;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      kCanvasWidth,
      kCanvasHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Future<Uint8List> frameToPng(Uint8List pixels) async {
    final rgba = Uint8List(kCanvasWidth * kCanvasHeight * 4);
    const bg = 0xFFDFDFDF;
    const fg = 0xFF000000;
    for (int i = 0; i < kCanvasWidth * kCanvasHeight; i++) {
      final c = pixels[i] != 0 ? fg : bg;
      rgba[i * 4] = (c >> 16) & 0xFF;
      rgba[i * 4 + 1] = (c >> 8) & 0xFF;
      rgba[i * 4 + 2] = c & 0xFF;
      rgba[i * 4 + 3] = (c >> 24) & 0xFF;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, kCanvasWidth, kCanvasHeight, ui.PixelFormat.rgba8888, completer.complete);
    final img = await completer.future;
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd!.buffer.asUint8List();
  }
}
