import 'dart:typed_data';

import '../bm.dart';
import 'elf.dart';
import 'manifest.dart';

const fapIconWidth = 10;
const fapIconHeight = 10;

class FapIconData {
  const FapIconData({required this.name, this.icon});
  final String name;
  final Uint8List? icon;
}

FapIconData? extractFapIcon(Uint8List fapBytes) {
  final section = ElfImage.parse(fapBytes)?.sectionBytes(kFapMetaSection);
  if (section == null) return null;

  final manifest = FapManifest.parse(section);
  if (manifest == null || manifest.magic != kFapMetaMagic) return null;
  if (manifest.name.isEmpty) return null;

  return FapIconData(
    name: manifest.name,
    icon: manifest.hasIcon ? _decodeIcon(manifest.icon) : null,
  );
}

Uint8List? _decodeIcon(Uint8List field) {
  try {
    final xbm = BmCodec.decodeBmFile(field);
    if (xbm == null) return null;
    final rowBytes = (fapIconWidth + 7) >> 3;
    if (xbm.length < rowBytes * fapIconHeight) return null;
    if (xbm.every((byte) => byte == 0)) return null;
    return xbm;
  } catch (_) {
    return null;
  }
}
