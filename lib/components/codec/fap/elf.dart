import 'dart:typed_data';
import 'readcs.dart';

const String kFapMetaSection = '.fapmeta';
const String kFapAssetsSection = '.fapassets';
const String kFapFastRelPrefix = '.fast.rel';

const int _shtNobits = 8;
const int _shtSymtab = 2;
const int _shfAlloc = 0x2;
const int _shfExecInstr = 0x4;
const int _shfWrite = 0x1;
const int _shfInfoLink = 0x40;

class ElfSectionHeader {
  const ElfSectionHeader({
    required this.index,
    required this.name,
    required this.type,
    required this.flags,
    required this.offset,
    required this.size,
    required this.link,
    required this.align,
  });

  final int index;
  final String name;
  final int type;
  final int flags;
  final int offset;
  final int size;
  final int link;
  final int align;

  bool get isAllocated => flags & _shfAlloc != 0;
  bool get isExecutable => flags & _shfExecInstr != 0;
  bool get isWritable => flags & _shfWrite != 0;
  bool get isInfoLink => flags & _shfInfoLink != 0;
  bool get isNoBits => type == _shtNobits;
}

/// Minimal ELF reader covering what a `.fap` needs: the section table, section
/// payloads and the symbol table.
class ElfImage {
  ElfImage._(this._bytes, this._data, this.is64Bit, this.endian, this.sections);

  final Uint8List _bytes;
  final ByteData _data;
  final bool is64Bit;
  final Endian endian;
  final List<ElfSectionHeader> sections;

  static ElfImage? parse(Uint8List bytes) {
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
    if (endian == null || (elfClass != 1 && elfClass != 2)) return null;

    final is64Bit = elfClass == 2;
    if (bytes.length < (is64Bit ? 64 : 52)) return null;

    final data = ByteData.sublistView(bytes);
    final tableOffset = is64Bit
        ? _checkedInt(data.getUint64(40, endian))
        : data.getUint32(32, endian);
    final headerSize = data.getUint16(is64Bit ? 58 : 46, endian);
    final headerCount = data.getUint16(is64Bit ? 60 : 48, endian);
    final nameIndex = data.getUint16(is64Bit ? 62 : 50, endian);

    if (tableOffset == null ||
        headerSize < (is64Bit ? 64 : 40) ||
        headerCount == 0 ||
        nameIndex >= headerCount ||
        !_hasRange(bytes.length, tableOffset, headerSize * headerCount)) {
      return null;
    }

    final raw = <ElfSectionHeader>[];
    for (var i = 0; i < headerCount; i++) {
      final base = tableOffset + i * headerSize;
      final offset = is64Bit
          ? _checkedInt(data.getUint64(base + 24, endian))
          : data.getUint32(base + 16, endian);
      final size = is64Bit
          ? _checkedInt(data.getUint64(base + 32, endian))
          : data.getUint32(base + 20, endian);
      final flags = is64Bit
          ? _checkedInt(data.getUint64(base + 8, endian))
          : data.getUint32(base + 8, endian);
      final align = is64Bit
          ? _checkedInt(data.getUint64(base + 48, endian))
          : data.getUint32(base + 32, endian);
      if (offset == null || size == null) return null;
      raw.add(
        ElfSectionHeader(
          index: i,
          name: '',
          type: data.getUint32(base + 4, endian),
          flags: flags ?? 0,
          offset: offset,
          size: size,
          link: data.getUint32(base + (is64Bit ? 40 : 24), endian),
          align: align ?? 0,
        ),
      );
    }

    final names = raw[nameIndex];
    if (!_hasRange(bytes.length, names.offset, names.size)) return null;
    final nameTable = Uint8List.sublistView(
      bytes,
      names.offset,
      names.offset + names.size,
    );

    final sections = <ElfSectionHeader>[];
    for (var i = 0; i < raw.length; i++) {
      final base = tableOffset + i * headerSize;
      final section = raw[i];
      sections.add(
        ElfSectionHeader(
          index: section.index,
          name: readCString(nameTable, data.getUint32(base, endian)) ?? '',
          type: section.type,
          flags: section.flags,
          offset: section.offset,
          size: section.size,
          link: section.link,
          align: section.align,
        ),
      );
    }

    return ElfImage._(bytes, data, is64Bit, endian, sections);
  }

  ElfSectionHeader? section(String name) {
    for (final section in sections) {
      if (section.name == name) return section;
    }
    return null;
  }

  Uint8List? sectionBytes(String name) {
    final header = section(name);
    return header == null ? null : bytesOf(header);
  }

  Uint8List? bytesOf(ElfSectionHeader header) {
    if (header.isNoBits) return Uint8List(0);
    if (!_hasRange(_bytes.length, header.offset, header.size)) return null;
    return Uint8List.sublistView(
      _bytes,
      header.offset,
      header.offset + header.size,
    );
  }

  /// Names of the symbols the file leaves undefined — on a `.fap` these are the
  /// firmware API entries the loader has to resolve at launch.
  List<String> undefinedSymbols() {
    if (is64Bit) return const [];
    final symtab = section('.symtab');
    if (symtab == null || symtab.type != _shtSymtab || symtab.size == 0) {
      return const [];
    }
    if (symtab.link >= sections.length) return const [];
    final strtab = sections[symtab.link];
    if (!_hasRange(_bytes.length, strtab.offset, strtab.size) ||
        !_hasRange(_bytes.length, symtab.offset, symtab.size)) {
      return const [];
    }
    final strings = Uint8List.sublistView(
      _bytes,
      strtab.offset,
      strtab.offset + strtab.size,
    );

    final out = <String>{};
    final count = symtab.size ~/ 16;
    for (var i = 0; i < count; i++) {
      final base = symtab.offset + i * 16;
      if (_data.getUint16(base + 14, endian) != 0) continue;
      final name = readCString(strings, _data.getUint32(base, endian));
      if (name != null && name.isNotEmpty) out.add(name);
    }
    final list = out.toList()..sort();
    return list;
  }
}


int? _checkedInt(int value) {
  if (value < 0 || value > 0x7fffffffffffffff) return null;
  return value;
}

bool _hasRange(int length, int offset, int size) =>
    offset >= 0 && size >= 0 && offset <= length - size;
