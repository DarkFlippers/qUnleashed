import 'dart:io' show zlib;
import 'dart:typed_data';

import 'models/models.dart';

/// Screenshot output matches the original qFlipper "Save Screenshot":
/// the 1-bit screen is rendered with an amber background and black pixels,
/// scaled 4× with crisp (nearest-neighbor) edges and written as an RGB PNG
/// without an alpha channel — exactly like `ScreenCanvas::saveImage(url, 4)`.
const int kScreenshotScale = 4;

/// qFlipper `StreamOverlay` colors: foreground "black", background
/// `Theme.color.lightorange2` (#fe8a2c). Hardcoded so the saved image looks
/// the same regardless of the app theme.
const int _bgR = 0xFE, _bgG = 0x8A, _bgB = 0x2C;
const int _fgR = 0x00, _fgG = 0x00, _fgB = 0x00;

/// Encodes [raw] into a PNG identical in size, color and format to qFlipper's
/// saved screenshots (512×256 for landscape, 256×512 for portrait, RGB8).
Uint8List encodeScreenshotPng(RawFrameData raw) {
  const srcW = 128;
  const srcH = 64;
  const scale = kScreenshotScale;

  final vertical =
      raw.orientation == StreamOrientation.vertical ||
      raw.orientation == StreamOrientation.verticalFlip;

  // Portrait orientations rotate the 128×64 buffer 90° clockwise, mirroring the
  // live view's RotatedBox(quarterTurns: 1).
  final preW = vertical ? srcH : srcW;
  final preH = vertical ? srcW : srcH;
  final outW = preW * scale;
  final outH = preH * scale;

  final idx = raw.pixelIndices;

  // One filtered scanline = 1 filter byte + outW*3 RGB bytes.
  final stride = outW * 3;
  final rows = Uint8List((stride + 1) * outH);

  for (var dy = 0; dy < outH; dy++) {
    final preY = dy ~/ scale;
    final rowBase = dy * (stride + 1) + 1; // skip filter byte (0 = None)
    for (var dx = 0; dx < outW; dx++) {
      final preX = dx ~/ scale;
      final int srcLit;
      if (vertical) {
        srcLit = idx[(srcH - 1 - preX) * srcW + preY];
      } else {
        srcLit = idx[preY * srcW + preX];
      }
      final p = rowBase + dx * 3;
      if (srcLit != 0) {
        rows[p] = _fgR;
        rows[p + 1] = _fgG;
        rows[p + 2] = _fgB;
      } else {
        rows[p] = _bgR;
        rows[p + 1] = _bgG;
        rows[p + 2] = _bgB;
      }
    }
  }

  return _buildPng(outW, outH, rows);
}

Uint8List _buildPng(int width, int height, Uint8List filteredRows) {
  final out = BytesBuilder(copy: false);
  out.add(const [137, 80, 78, 71, 13, 10, 26, 10]);

  final ihdr = Uint8List(13);
  final hd = ByteData.view(ihdr.buffer);
  hd.setUint32(0, width);
  hd.setUint32(4, height);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // color type: truecolor RGB (no alpha)
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace
  out.add(_chunk('IHDR', ihdr));

  final compressed = Uint8List.fromList(zlib.encode(filteredRows));
  out.add(_chunk('IDAT', compressed));
  out.add(_chunk('IEND', Uint8List(0)));

  return out.toBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final chunk = Uint8List(8 + data.length + 4);
  final view = ByteData.view(chunk.buffer);
  view.setUint32(0, data.length);
  chunk.setRange(4, 8, typeBytes);
  chunk.setRange(8, 8 + data.length, data);

  final crc = _crc32(chunk, 4, 8 + data.length);
  view.setUint32(8 + data.length, crc);
  return chunk;
}

final Uint32List _crcTable = _makeCrcTable();

Uint32List _makeCrcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xFFFFFFFF;
  for (var i = start; i < end; i++) {
    crc = _crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
