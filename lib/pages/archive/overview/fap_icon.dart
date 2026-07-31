import 'dart:typed_data';

import '../../../components/codec/bm.dart';
import '../../../components/codec/fap.dart';

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

FapIconData? extract(Uint8List fapBytes) => extractFapIcon(fapBytes);

/// Decodes the manifest icon field, which is a Flipper "bm" payload (optionally
/// heatshrink-compressed), into raw XBM bits. Returns `null` if it cannot be
/// decoded or is too short for a [fapIconWidth]×[fapIconHeight] image.
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
