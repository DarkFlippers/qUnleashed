import 'dart:convert';
import 'dart:typed_data';

import '../paint/codec.dart';

const _manifestMagic = 0x52474448;

// Layout of `FlipperApplicationManifestV1` inside the `.fapmeta` section
// (`#pragma pack(1)`), see firmware `application_manifest.h`:
//   base header (magic, version, api_version, hw_target) = 14 bytes
//   stack_size (2) + app_version (4) → name starts at 20
//   name[32] → has_icon at 52 → icon[32] at 53.
const _nameOffset = 14 + 2 + 4;
const _nameLen = 32;
const _hasIconOffset = _nameOffset + _nameLen;
const _iconOffset = _hasIconOffset + 1;
const _iconLen = 32;
const _minManifestLen = _iconOffset + _iconLen;

/// Icon dimensions used by Flipper application manifests.
const fapIconWidth = 10;
const fapIconHeight = 10;

/// Extracted icon data and the app name discovered alongside it.
class FapIconData {
  const FapIconData({required this.name, this.icon});

  final String name;

  /// Decoded 1bpp XBM bits for a [fapIconWidth]×[fapIconHeight] icon: row-major,
  /// 2 bytes per row, bit 0 is the leftmost pixel. `null` when the app declares
  /// no icon or it could not be decoded; callers fall back to a default icon.
  final Uint8List? icon;
}

/// Parses a `.fap` ELF file and returns its embedded app name and icon.
///
/// Returns `null` if the bytes are not a valid ELF, there is no `.fapmeta`
/// section, the manifest magic does not match, or the name is not readable.
/// A valid result may still have a `null` [FapIconData.icon] when the app
/// ships without an icon.
FapIconData? extractFapIcon(Uint8List fapBytes) {
  final fapMeta = _readElfSection(fapBytes, '.fapmeta');
  if (fapMeta == null || fapMeta.length < _minManifestLen) {
    return null;
  }

  final data = ByteData.sublistView(fapMeta);
  if (data.getUint32(0, Endian.little) != _manifestMagic) {
    return null;
  }

  final name = _readName(fapMeta, _nameOffset, _nameLen);
  if (name == null) {
    return null;
  }

  Uint8List? icon;
  if (fapMeta[_hasIconOffset] != 0) {
    icon = _decodeIcon(
      Uint8List.sublistView(fapMeta, _iconOffset, _iconOffset + _iconLen),
    );
  }

  return FapIconData(name: name, icon: icon);
}

FapIconData? extract(Uint8List fapBytes) => extractFapIcon(fapBytes);

/// Decodes the manifest icon field, which is a Flipper "bm" payload (optionally
/// heatshrink-compressed), into raw XBM bits. Returns `null` if it cannot be
/// decoded or is too short for a [fapIconWidth]×[fapIconHeight] image.
Uint8List? _decodeIcon(Uint8List field) {
  try {
    final xbm = PaintCodec.decodeBmFile(field);
    if (xbm == null) return null;
    final rowBytes = (fapIconWidth + 7) >> 3;
    if (xbm.length < rowBytes * fapIconHeight) return null;
    if (xbm.every((byte) => byte == 0)) return null;
    return xbm;
  } catch (_) {
    return null;
  }
}

String? _readName(Uint8List bytes, int offset, int maxLen) {
  final end = offset + maxLen;
  var nul = offset;
  while (nul < end && bytes[nul] != 0) {
    nul++;
  }
  if (nul == offset) return null;
  for (var i = offset; i < nul; i++) {
    final byte = bytes[i];
    if (!((byte >= 0x21 && byte <= 0x7e) || byte == 0x20)) {
      return null;
    }
  }
  return ascii.decode(bytes.sublist(offset, nul), allowInvalid: false);
}

Uint8List? _readElfSection(Uint8List bytes, String sectionName) {
  if (bytes.length < 16 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    return null;
  }

  final elfClass = bytes[4];
  final endian = switch (bytes[5]) {
    1 => Endian.little,
    2 => Endian.big,
    _ => null,
  };
  if (endian == null || (elfClass != 1 && elfClass != 2)) {
    return null;
  }

  final data = ByteData.sublistView(bytes);
  final is64Bit = elfClass == 2;
  if (bytes.length < (is64Bit ? 64 : 52)) {
    return null;
  }

  final sectionHeaderOffset = is64Bit
      ? _checkedInt(data.getUint64(40, endian))
      : data.getUint32(32, endian);
  final sectionHeaderSize = data.getUint16(is64Bit ? 58 : 46, endian);
  final sectionHeaderCount = data.getUint16(is64Bit ? 60 : 48, endian);
  final sectionNameIndex = data.getUint16(is64Bit ? 62 : 50, endian);

  if (sectionHeaderOffset == null ||
      sectionHeaderSize == 0 ||
      sectionHeaderCount == 0 ||
      sectionNameIndex >= sectionHeaderCount) {
    return null;
  }

  final tableSize = sectionHeaderSize * sectionHeaderCount;
  if (!_hasRange(bytes.length, sectionHeaderOffset, tableSize)) {
    return null;
  }

  final nameTableHeader =
      sectionHeaderOffset + sectionNameIndex * sectionHeaderSize;
  final nameTable = _readSectionBytes(
    bytes,
    data,
    nameTableHeader,
    sectionHeaderSize,
    is64Bit,
    endian,
  );
  if (nameTable == null) {
    return null;
  }

  for (var i = 0; i < sectionHeaderCount; i++) {
    final headerOffset = sectionHeaderOffset + i * sectionHeaderSize;
    if (!_hasRange(bytes.length, headerOffset, sectionHeaderSize)) {
      return null;
    }

    final nameOffset = data.getUint32(headerOffset, endian);
    final name = _readCString(nameTable, nameOffset);
    if (name != sectionName) {
      continue;
    }

    return _readSectionBytes(
      bytes,
      data,
      headerOffset,
      sectionHeaderSize,
      is64Bit,
      endian,
    );
  }

  return null;
}

Uint8List? _readSectionBytes(
  Uint8List bytes,
  ByteData data,
  int headerOffset,
  int headerSize,
  bool is64Bit,
  Endian endian,
) {
  final requiredHeaderSize = is64Bit ? 64 : 40;
  if (headerSize < requiredHeaderSize) {
    return null;
  }

  final offset = is64Bit
      ? _checkedInt(data.getUint64(headerOffset + 24, endian))
      : data.getUint32(headerOffset + 16, endian);
  final size = is64Bit
      ? _checkedInt(data.getUint64(headerOffset + 32, endian))
      : data.getUint32(headerOffset + 20, endian);

  if (offset == null ||
      size == null ||
      !_hasRange(bytes.length, offset, size)) {
    return null;
  }

  return Uint8List.sublistView(bytes, offset, offset + size);
}

String? _readCString(Uint8List bytes, int offset) {
  if (offset < 0 || offset >= bytes.length) {
    return null;
  }

  var end = offset;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }

  return ascii.decode(bytes.sublist(offset, end), allowInvalid: true);
}

int? _checkedInt(int value) {
  if (value < 0 || value > 0x7fffffffffffffff) {
    return null;
  }
  return value;
}

bool _hasRange(int length, int offset, int size) {
  return offset >= 0 && size >= 0 && offset <= length - size;
}
