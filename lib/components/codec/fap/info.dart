import 'dart:typed_data';
import 'manifest.dart';
import 'elf.dart';
import 'assets.dart';

/// Everything worth knowing about a `.fap` that can be read from the file
/// itself, without the catalog and without launching it on a device.
class FapInfo {
  const FapInfo({
    required this.fileSize,
    required this.manifest,
    required this.sections,
    required this.imports,
    required this.assets,
    required this.hasFastRelocations,
  });

  final int fileSize;
  final FapManifest? manifest;
  final List<ElfSectionHeader> sections;
  final List<String> imports;
  final FapAssets? assets;
  final bool hasFastRelocations;

  static FapInfo? parse(Uint8List bytes) {
    final elf = ElfImage.parse(bytes);
    if (elf == null) return null;

    final metaSection = elf.sectionBytes(kFapMetaSection);
    final assetsSection = elf.sectionBytes(kFapAssetsSection);

    return FapInfo(
      fileSize: bytes.length,
      manifest: metaSection == null ? null : FapManifest.parse(metaSection),
      sections: List.unmodifiable(elf.sections),
      imports: List.unmodifiable(elf.undefinedSymbols()),
      assets: assetsSection == null ? null : FapAssets.parse(assetsSection),
      hasFastRelocations: elf.sections.any(
        (s) => s.name.startsWith(kFapFastRelPrefix) && !_isArmSection(s.name),
      ),
    );
  }

  bool get isValid => manifest?.isValid ?? false;

  /// Sections the loader copies into the heap, in the order firmware
  /// `elf_preload_section()` decides on them.
  List<ElfSectionHeader> get loadedSections => sections
      .where(
        (s) =>
            s.size > 0 &&
            !_isArmSection(s.name) &&
            (s.isAllocated ||
                (!s.isInfoLink && s.name.startsWith(kFapFastRelPrefix))),
      )
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