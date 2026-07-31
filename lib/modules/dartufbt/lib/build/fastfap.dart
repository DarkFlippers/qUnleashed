import 'dart:io';
import 'dart:typed_data';

import 'elf_reader.dart';

class FastFapSection {
  const FastFapSection(this.name, this.data);

  final String name;
  final Uint8List data;
}

class FastFap {
  const FastFap();

  static const int version = 1;
  static const String relPrefix = '.rel';
  static const String fastRelPrefix = '.fast.rel';

  static int gnuSymHash(String name) {
    var hash = 0x1505;
    for (final code in name.codeUnits) {
      hash = ((hash << 5) + hash + code) & 0xFFFFFFFF;
    }
    return hash;
  }

  List<FastFapSection> buildSections(File fap) {
    final elf = ElfFile(fap.readAsBytesSync());
    final symtab = elf.symtab;
    if (symtab == null) throw const FormatException('No symbol table found');

    final relocationSections = elf.relocationSections;
    if (relocationSections.isEmpty) return const [];

    final symbols = elf.readSymbols(symtab);
    final result = <FastFapSection>[];

    for (final section in relocationSections) {
      if (!section.name.startsWith(relPrefix)) {
        throw FormatException(
          'Unknown relocation section name: ${section.name}',
        );
      }

      final unique = <String, _UniqueRelocation>{};
      for (final relocation in elf.readRelocations(section)) {
        final symbol = symbols[relocation.symbolIndex];
        final sectionIndex = symbol.sectionIndex;
        final key =
            '$sectionIndex|${symbol.value}|${relocation.type}|'
            '${symbol.name}';
        (unique[key] ??= _UniqueRelocation(
          sectionIndex,
          symbol.value,
          relocation.type,
          symbol.name,
        )).offsets.add(relocation.offset);
      }

      result.add(
        FastFapSection(
          '$fastRelPrefix${section.name.substring(relPrefix.length)}',
          _serialize(unique.values.toList()),
        ),
      );
    }
    return result;
  }

  static Uint8List _serialize(List<_UniqueRelocation> relocations) {
    final out = BytesBuilder();
    out.addByte(version);
    out.add(_u32(relocations.length));

    for (final relocation in relocations) {
      if (relocation.section > 0) {
        out.addByte((1 << 7) | (relocation.type & 0x7F));
        out.add(_u32(relocation.section));
        out.add(_u32(relocation.sectionValue));
      } else {
        out.addByte(relocation.type & 0x7F);
        out.add(_u32(gnuSymHash(relocation.name)));
      }

      out.add(_u32(relocation.offsets.length));
      for (final offset in relocation.offsets) {
        out.addByte(offset & 0xFF);
        out.addByte((offset >> 8) & 0xFF);
        out.addByte((offset >> 16) & 0xFF);
      }
    }
    return out.toBytes();
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}

class _UniqueRelocation {
  _UniqueRelocation(this.section, this.sectionValue, this.type, this.name);

  final int section;
  final int sectionValue;
  final int type;
  final String name;
  final List<int> offsets = [];
}
