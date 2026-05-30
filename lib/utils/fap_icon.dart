import 'dart:convert';
import 'dart:typed_data';

const _manifestMagic = 0x52474448;
const _nameLen = 32;
const _iconLen = 32;

/// Extracted icon data and the app name discovered alongside it.
///
/// The icon bytes are XBM-format data used by Flipper canvas: row-major,
/// 2 bytes per row for 10 pixels, bit 0 is the leftmost pixel.
class FapIconData {
  const FapIconData({required this.icon, required this.name});

  final Uint8List icon;
  final String name;
}

/// Parses a `.fap` ELF file and returns its embedded icon, if present.
///
/// Returns `null` if the bytes are not a valid ELF, there is no `.fapmeta`
/// section, the manifest magic does not match, no plausible name/icon pair is
/// found, or the icon slot is entirely zeroed.
FapIconData? extractFapIcon(Uint8List fapBytes) {
  final fapMeta = _readElfSection(fapBytes, '.fapmeta');
  if (fapMeta == null || fapMeta.length < 8 + _nameLen + _iconLen) {
    return null;
  }

  final data = ByteData.sublistView(fapMeta);
  if (data.getUint32(0, Endian.little) != _manifestMagic) {
    return null;
  }

  final last = fapMeta.length - _nameLen - _iconLen;
  for (var offset = 8; offset <= last; offset++) {
    final name = _tryReadName(fapMeta.sublist(offset, offset + _nameLen));
    if (name == null) {
      continue;
    }

    final iconStart = offset + _nameLen;
    final icon = fapMeta.sublist(iconStart, iconStart + _iconLen);
    if (icon.every((byte) => byte == 0)) {
      continue;
    }

    return FapIconData(icon: Uint8List.fromList(icon), name: name);
  }

  return null;
}

FapIconData? extract(Uint8List fapBytes) => extractFapIcon(fapBytes);

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

String? _tryReadName(Uint8List slice) {
  if (slice.length != _nameLen) {
    return null;
  }

  final firstNull = slice.indexOf(0);
  if (firstNull < 1 || firstNull >= _nameLen) {
    return null;
  }

  for (var i = 0; i < firstNull; i++) {
    final byte = slice[i];
    if (!((byte >= 0x21 && byte <= 0x7e) || byte == 0x20)) {
      return null;
    }
  }

  for (var i = firstNull; i < slice.length; i++) {
    if (slice[i] != 0) {
      return null;
    }
  }

  return ascii.decode(slice.sublist(0, firstNull), allowInvalid: false);
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
