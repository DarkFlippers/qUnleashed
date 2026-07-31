import 'dart:convert';
import 'dart:typed_data';

const int kFapMetaMagic = 0x52474448;
const int kFapMetaVersion = 1;
const int kFapAssetsMagic = 0x4F4C5A44;
const int kFapAssetsVersion = 1;

const String kFapMetaSection = '.fapmeta';
const String kFapAssetsSection = '.fapassets';
const String kFapDebugLinkSection = '.gnu_debuglink';
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
      raw.add(ElfSectionHeader(
        index: i,
        name: '',
        type: data.getUint32(base + 4, endian),
        flags: flags ?? 0,
        offset: offset,
        size: size,
        link: data.getUint32(base + (is64Bit ? 40 : 24), endian),
        align: align ?? 0,
      ));
    }

    final names = raw[nameIndex];
    if (!_hasRange(bytes.length, names.offset, names.size)) return null;
    final nameTable =
        Uint8List.sublistView(bytes, names.offset, names.offset + names.size);

    final sections = <ElfSectionHeader>[];
    for (var i = 0; i < raw.length; i++) {
      final base = tableOffset + i * headerSize;
      final section = raw[i];
      sections.add(ElfSectionHeader(
        index: section.index,
        name: _readCString(nameTable, data.getUint32(base, endian)) ?? '',
        type: section.type,
        flags: section.flags,
        offset: section.offset,
        size: section.size,
        link: section.link,
        align: section.align,
      ));
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
      final name = _readCString(strings, _data.getUint32(base, endian));
      if (name != null && name.isNotEmpty) out.add(name);
    }
    final list = out.toList()..sort();
    return list;
  }
}

/// `FlipperApplicationManifestV1` from the `.fapmeta` section, see firmware
/// `lib/flipper_application/application_manifest.h`.
class FapManifest {
  const FapManifest({
    required this.magic,
    required this.manifestVersion,
    required this.apiMajor,
    required this.apiMinor,
    required this.hardwareTarget,
    required this.stackSize,
    required this.versionMajor,
    required this.versionMinor,
    required this.name,
    required this.hasIcon,
    required this.icon,
  });

  static const int nameOffset = 14 + 2 + 4;
  static const int nameLength = 32;
  static const int hasIconOffset = nameOffset + nameLength;
  static const int iconOffset = hasIconOffset + 1;
  static const int iconLength = 32;
  static const int structSize = iconOffset + iconLength;

  final int magic;
  final int manifestVersion;
  final int apiMajor;
  final int apiMinor;
  final int hardwareTarget;
  final int stackSize;
  final int versionMajor;
  final int versionMinor;
  final String name;
  final bool hasIcon;
  final Uint8List icon;

  bool get isValid =>
      magic == kFapMetaMagic && manifestVersion == kFapMetaVersion;

  bool get isPlugin => stackSize == 0;

  String get api => '$apiMajor.$apiMinor';

  String get version => '$versionMajor.$versionMinor';

  String get target => 'f$hardwareTarget';

  static FapManifest? parse(Uint8List section) {
    if (section.length < structSize) return null;
    final data = ByteData.sublistView(section);
    return FapManifest(
      magic: data.getUint32(0, Endian.little),
      manifestVersion: data.getUint32(4, Endian.little),
      apiMinor: data.getUint16(8, Endian.little),
      apiMajor: data.getUint16(10, Endian.little),
      hardwareTarget: data.getUint16(12, Endian.little),
      stackSize: data.getUint16(14, Endian.little),
      versionMinor: data.getUint16(16, Endian.little),
      versionMajor: data.getUint16(18, Endian.little),
      name: _readFixedAscii(section, nameOffset, nameLength),
      hasIcon: section[hasIconOffset] != 0,
      icon: Uint8List.sublistView(
        section,
        iconOffset,
        iconOffset + iconLength,
      ),
    );
  }
}

class FapAssetFile {
  const FapAssetFile({required this.path, required this.size});

  final String path;
  final int size;
}

/// Contents of the `.fapassets` bundle, the format written by
/// `FileBundler` and unpacked by firmware `application_assets.c`.
class FapAssets {
  const FapAssets({
    required this.dirs,
    required this.files,
    required this.signature,
  });

  final List<String> dirs;
  final List<FapAssetFile> files;
  final String signature;

  int get totalSize {
    var total = 0;
    for (final file in files) {
      total += file.size;
    }
    return total;
  }

  List<FapAssetFile> get plugins => files
      .where((f) => f.path.startsWith('plugins/') && f.path.endsWith('.fal'))
      .toList();

  static FapAssets? parse(Uint8List section) {
    if (section.length < 20) return null;
    final data = ByteData.sublistView(section);
    if (data.getUint32(0, Endian.little) != kFapAssetsMagic) return null;
    if (data.getUint32(4, Endian.little) != kFapAssetsVersion) return null;

    final dirsCount = data.getUint32(8, Endian.little);
    final filesCount = data.getUint32(12, Endian.little);

    var cursor = 16;

    Uint8List? take(int length) {
      if (length < 0 || cursor + length > section.length) return null;
      final out = Uint8List.sublistView(section, cursor, cursor + length);
      cursor += length;
      return out;
    }

    int? takeLength() {
      if (cursor + 4 > section.length) return null;
      final value = data.getUint32(cursor, Endian.little);
      cursor += 4;
      return value;
    }

    final signatureLength = takeLength();
    if (signatureLength == null) return null;
    final signature = take(signatureLength);
    if (signature == null) return null;

    final dirs = <String>[];
    for (var i = 0; i < dirsCount; i++) {
      final length = takeLength();
      if (length == null) return null;
      final raw = take(length);
      if (raw == null) return null;
      dirs.add(_readCString(raw, 0) ?? '');
    }

    final files = <FapAssetFile>[];
    for (var i = 0; i < filesCount; i++) {
      final nameLength = takeLength();
      if (nameLength == null) return null;
      final raw = take(nameLength);
      if (raw == null) return null;
      final size = takeLength();
      if (size == null) return null;
      if (take(size) == null) return null;
      files.add(FapAssetFile(path: _readCString(raw, 0) ?? '', size: size));
    }

    return FapAssets(
      dirs: dirs,
      files: files,
      signature: _hex(signature),
    );
  }
}

/// Everything worth knowing about a `.fap` that can be read from the file
/// itself, without the catalog and without launching it on a device.
class FapInfo {
  const FapInfo({
    required this.fileSize,
    required this.manifest,
    required this.sections,
    required this.imports,
    required this.assets,
    required this.debugLink,
    required this.hasFastRelocations,
  });

  final int fileSize;
  final FapManifest? manifest;
  final List<ElfSectionHeader> sections;
  final List<String> imports;
  final FapAssets? assets;
  final String? debugLink;
  final bool hasFastRelocations;

  static FapInfo? parse(Uint8List bytes) {
    final elf = ElfImage.parse(bytes);
    if (elf == null) return null;

    final metaSection = elf.sectionBytes(kFapMetaSection);
    final assetsSection = elf.sectionBytes(kFapAssetsSection);
    final debugLinkSection = elf.sectionBytes(kFapDebugLinkSection);

    return FapInfo(
      fileSize: bytes.length,
      manifest: metaSection == null ? null : FapManifest.parse(metaSection),
      sections: List.unmodifiable(elf.sections),
      imports: List.unmodifiable(elf.undefinedSymbols()),
      assets: assetsSection == null ? null : FapAssets.parse(assetsSection),
      debugLink: debugLinkSection == null
          ? null
          : _readCString(debugLinkSection, 0),
      hasFastRelocations: elf.sections.any(
        (s) => s.name.startsWith(kFapFastRelPrefix) && !_isArmSection(s.name),
      ),
    );
  }

  bool get isValid => manifest?.isValid ?? false;

  /// Sections the loader copies into the heap, in the order firmware
  /// `elf_preload_section()` decides on them.
  List<ElfSectionHeader> get loadedSections => sections
      .where((s) =>
          s.size > 0 &&
          !_isArmSection(s.name) &&
          (s.isAllocated ||
              (!s.isInfoLink && s.name.startsWith(kFapFastRelPrefix))))
      .toList();

  /// Total heap the app needs once every loadable section is allocated.
  int get ramTotal {
    var total = 0;
    for (final section in loadedSections) {
      total += section.size;
    }
    return total;
  }

  /// Largest single allocation; the loader bails out when the biggest free
  /// block is smaller than this plus 1024 bytes.
  int get ramLargestBlock {
    var largest = 0;
    for (final section in loadedSections) {
      if (section.size > largest) largest = section.size;
    }
    return largest;
  }

  int get codeSize => _sumWhere((s) => s.isExecutable);

  int get dataSize =>
      _sumWhere((s) => !s.isExecutable && s.isWritable && !s.isNoBits);

  int get bssSize => _sumWhere((s) => s.isNoBits);

  int get readOnlyDataSize =>
      _sumWhere((s) => !s.isExecutable && !s.isWritable && !s.isNoBits);

  int get relocationSize {
    var total = 0;
    for (final section in loadedSections) {
      if (section.name.startsWith(kFapFastRelPrefix)) total += section.size;
    }
    return total;
  }

  int _sumWhere(bool Function(ElfSectionHeader) test) {
    var total = 0;
    for (final section in loadedSections) {
      if (section.name.startsWith(kFapFastRelPrefix)) continue;
      if (test(section)) total += section.size;
    }
    return total;
  }
}

bool _isArmSection(String name) =>
    name.startsWith('.ARM.') ||
    name.startsWith('.rel.ARM.') ||
    name.startsWith('.fast.rel.ARM.');

String _readFixedAscii(Uint8List bytes, int offset, int maxLength) {
  final end = offset + maxLength;
  final out = StringBuffer();
  for (var i = offset; i < end && i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte == 0) break;
    if (byte < 0x20 || byte > 0x7e) return '';
    out.writeCharCode(byte);
  }
  return out.toString();
}

String? _readCString(Uint8List bytes, int offset) {
  if (offset < 0 || offset >= bytes.length) return null;
  var end = offset;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }
  return ascii.decode(bytes.sublist(offset, end), allowInvalid: true);
}

String _hex(Uint8List bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

int? _checkedInt(int value) {
  if (value < 0 || value > 0x7fffffffffffffff) return null;
  return value;
}

bool _hasRange(int length, int offset, int size) =>
    offset >= 0 && size >= 0 && offset <= length - size;
