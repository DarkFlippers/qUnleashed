import 'dart:typed_data';

class ElfSection {
  const ElfSection({
    required this.index,
    required this.name,
    required this.type,
    required this.offset,
    required this.size,
    required this.link,
    required this.info,
    required this.entrySize,
  });

  static const int typeSymtab = 2;
  static const int typeRel = 9;

  final int index;
  final String name;
  final int type;
  final int offset;
  final int size;
  final int link;
  final int info;
  final int entrySize;
}

class ElfSymbol {
  const ElfSymbol({
    required this.name,
    required this.value,
    required this.sectionIndex,
  });

  static const int sectionUndefined = 0;

  final String name;
  final int value;
  final int sectionIndex;
}

class ElfRelocation {
  const ElfRelocation({
    required this.offset,
    required this.symbolIndex,
    required this.type,
  });

  final int offset;
  final int symbolIndex;
  final int type;
}

class ElfFile {
  ElfFile(this.bytes) : _data = ByteData.sublistView(bytes) {
    _parse();
  }

  static const int _sectionHeaderSize = 40;
  static const int _symbolSize = 16;
  static const int _relocationSize = 8;

  final Uint8List bytes;
  final ByteData _data;
  final List<ElfSection> sections = [];

  ElfSection? get symtab {
    for (final section in sections) {
      if (section.type == ElfSection.typeSymtab) return section;
    }
    return null;
  }

  List<ElfSection> get relocationSections =>
      sections.where((section) => section.type == ElfSection.typeRel).toList();

  List<ElfSymbol> readSymbols(ElfSection section) {
    final stringsOffset = sections[section.link].offset;
    final count = section.size ~/ _symbolSize;
    return List<ElfSymbol>.generate(count, (i) {
      final base = section.offset + i * _symbolSize;
      return ElfSymbol(
        name: _readString(stringsOffset + _data.getUint32(base, Endian.little)),
        value: _data.getUint32(base + 4, Endian.little),
        sectionIndex: _data.getUint16(base + 14, Endian.little),
      );
    });
  }

  List<ElfRelocation> readRelocations(ElfSection section) {
    final count = section.size ~/ _relocationSize;
    return List<ElfRelocation>.generate(count, (i) {
      final base = section.offset + i * _relocationSize;
      final info = _data.getUint32(base + 4, Endian.little);
      return ElfRelocation(
        offset: _data.getUint32(base, Endian.little),
        symbolIndex: info >> 8,
        type: info & 0xFF,
      );
    });
  }

  void _parse() {
    if (bytes.length < 52 ||
        bytes[0] != 0x7F ||
        bytes[1] != 0x45 ||
        bytes[2] != 0x4C ||
        bytes[3] != 0x46) {
      throw const FormatException('Not an ELF file');
    }
    if (bytes[4] != 1) throw const FormatException('Only ELF32 is supported');
    if (bytes[5] != 1) {
      throw const FormatException('Only little-endian ELF is supported');
    }

    final shoff = _data.getUint32(0x20, Endian.little);
    final shentsize = _data.getUint16(0x2E, Endian.little);
    final shnum = _data.getUint16(0x30, Endian.little);
    final shstrndx = _data.getUint16(0x32, Endian.little);
    final stride = shentsize == 0 ? _sectionHeaderSize : shentsize;

    final names = <int>[];
    for (var i = 0; i < shnum; i++) {
      final base = shoff + i * stride;
      names.add(_data.getUint32(base, Endian.little));
      sections.add(
        ElfSection(
          index: i,
          name: '',
          type: _data.getUint32(base + 4, Endian.little),
          offset: _data.getUint32(base + 16, Endian.little),
          size: _data.getUint32(base + 20, Endian.little),
          link: _data.getUint32(base + 24, Endian.little),
          info: _data.getUint32(base + 28, Endian.little),
          entrySize: _data.getUint32(base + 36, Endian.little),
        ),
      );
    }

    final stringsOffset = sections[shstrndx].offset;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      sections[i] = ElfSection(
        index: section.index,
        name: _readString(stringsOffset + names[i]),
        type: section.type,
        offset: section.offset,
        size: section.size,
        link: section.link,
        info: section.info,
        entrySize: section.entrySize,
      );
    }
  }

  String _readString(int offset) {
    var end = offset;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return String.fromCharCodes(bytes.sublist(offset, end));
  }
}
