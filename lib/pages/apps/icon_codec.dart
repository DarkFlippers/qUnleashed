import 'dart:io' as io;
import 'dart:typed_data';

import '../archive/overview/fap_icon.dart' show fapIconWidth, fapIconHeight;

Uint8List? decodeCatalogIconToFapBits(Uint8List png) {
  try {
    final grid = _decodePngInk(png);
    if (grid == null) return null;
    return _packInkToFapBits(grid);
  } catch (_) {
    return null;
  }
}

class _InkGrid {
  _InkGrid(this.width, this.height, this.ink);
  final int width;
  final int height;
  final List<bool> ink;

  bool at(int x, int y) => ink[y * width + x];
}

Uint8List _packInkToFapBits(_InkGrid grid) {
  const w = fapIconWidth;
  const h = fapIconHeight;
  final rowBytes = (w + 7) >> 3;
  final out = Uint8List(rowBytes * h);
  for (var y = 0; y < h; y++) {
    final sy = grid.height == h ? y : (y * grid.height) ~/ h;
    for (var x = 0; x < w; x++) {
      final sx = grid.width == w ? x : (x * grid.width) ~/ w;
      if (!grid.at(sx, sy)) continue;
      out[y * rowBytes + (x >> 3)] |= 1 << (x & 7);
    }
  }
  return out;
}

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

_InkGrid? _decodePngInk(Uint8List bytes) {
  if (bytes.length < 8) return null;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }

  int? width, height, bitDepth, colorType, interlace;
  Uint8List? palette;
  Uint8List? transparency;
  final idat = BytesBuilder(copy: false);

  final data = ByteData.sublistView(bytes);
  var pos = 8;
  while (pos + 8 <= bytes.length) {
    final length = data.getUint32(pos, Endian.big);
    final type = String.fromCharCodes(bytes, pos + 4, pos + 8);
    final chunkStart = pos + 8;
    if (chunkStart + length > bytes.length) break;
    switch (type) {
      case 'IHDR':
        width = data.getUint32(chunkStart, Endian.big);
        height = data.getUint32(chunkStart + 4, Endian.big);
        bitDepth = bytes[chunkStart + 8];
        colorType = bytes[chunkStart + 9];
        interlace = bytes[chunkStart + 12];
      case 'PLTE':
        palette = Uint8List.sublistView(bytes, chunkStart, chunkStart + length);
      case 'tRNS':
        transparency = Uint8List.sublistView(
          bytes,
          chunkStart,
          chunkStart + length,
        );
      case 'IDAT':
        idat.add(Uint8List.sublistView(bytes, chunkStart, chunkStart + length));
      case 'IEND':
        pos = bytes.length;
        continue;
    }
    pos = chunkStart + length + 4;
  }

  if (width == null ||
      height == null ||
      bitDepth == null ||
      colorType == null ||
      width <= 0 ||
      height <= 0) {
    return null;
  }
  if (interlace != null && interlace != 0) return null;

  final channels = switch (colorType) {
    0 => 1,
    2 => 3,
    3 => 1,
    4 => 2,
    6 => 4,
    _ => 0,
  };
  if (channels == 0) return null;
  if (colorType == 3 && palette == null) return null;

  final raw = io.zlib.decode(idat.takeBytes());
  final rowBytes = (width * channels * bitDepth + 7) >> 3;
  if (raw.length < (rowBytes + 1) * height) return null;

  final recon = _unfilter(raw, width, height, channels, bitDepth, rowBytes);
  if (recon == null) return null;

  final maxSample = (1 << bitDepth) - 1;
  final ink = List<bool>.filled(width * height, false);
  for (var y = 0; y < height; y++) {
    final rowOff = y * rowBytes;
    for (var x = 0; x < width; x++) {
      ink[y * width + x] = _isInk(
        recon,
        rowOff,
        x,
        colorType,
        bitDepth,
        channels,
        maxSample,
        palette,
        transparency,
      );
    }
  }
  return _InkGrid(width, height, ink);
}

Uint8List? _unfilter(
  List<int> raw,
  int width,
  int height,
  int channels,
  int bitDepth,
  int rowBytes,
) {
  final bpp = ((channels * bitDepth + 7) >> 3).clamp(1, 8);
  final out = Uint8List(rowBytes * height);
  var src = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[src++];
    final rowStart = y * rowBytes;
    final prevStart = rowStart - rowBytes;
    for (var i = 0; i < rowBytes; i++) {
      final x = raw[src++] & 0xff;
      final a = i >= bpp ? out[rowStart + i - bpp] : 0;
      final b = y > 0 ? out[prevStart + i] : 0;
      final c = (y > 0 && i >= bpp) ? out[prevStart + i - bpp] : 0;
      final value = switch (filter) {
        0 => x,
        1 => x + a,
        2 => x + b,
        3 => x + ((a + b) >> 1),
        4 => x + _paeth(a, b, c),
        _ => null,
      };
      if (value == null) return null;
      out[rowStart + i] = value & 0xff;
    }
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

bool _isInk(
  Uint8List row,
  int rowOff,
  int x,
  int colorType,
  int bitDepth,
  int channels,
  int maxSample,
  Uint8List? palette,
  Uint8List? transparency,
) {
  int sampleAt(int channel) {
    if (bitDepth == 8) {
      return row[rowOff + x * channels + channel] & 0xff;
    }
    if (bitDepth == 16) {
      return row[rowOff + (x * channels + channel) * 2] & 0xff;
    }
    final bitPos = (x * channels + channel) * bitDepth;
    final byteIndex = rowOff + (bitPos >> 3);
    final shift = 8 - bitDepth - (bitPos & 7);
    return (row[byteIndex] >> shift) & maxSample;
  }

  int scale(int v) => maxSample == 0 ? 0 : (v * 255 / maxSample).round();

  switch (colorType) {
    case 0:
      return scale(sampleAt(0)) < 128;
    case 4:
      if (scale(sampleAt(1)) < 128) return false;
      return scale(sampleAt(0)) < 128;
    case 2:
      return _luminance(sampleAt(0), sampleAt(1), sampleAt(2)) < 128;
    case 6:
      if (sampleAt(3) < 128) return false;
      return _luminance(sampleAt(0), sampleAt(1), sampleAt(2)) < 128;
    case 3:
      final idx = sampleAt(0);
      if (transparency != null &&
          idx < transparency.length &&
          transparency[idx] < 128) {
        return false;
      }
      final pal = palette!;
      final base = idx * 3;
      if (base + 2 >= pal.length) return false;
      return _luminance(pal[base], pal[base + 1], pal[base + 2]) < 128;
    default:
      return false;
  }
}

int _luminance(int r, int g, int b) => (r * 299 + g * 587 + b * 114) ~/ 1000;
