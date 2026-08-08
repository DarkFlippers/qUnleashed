import 'dart:typed_data';

const int kFapMetaMagic = 0x52474448;
const int kFapMetaVersion = 1;

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
      icon: Uint8List.sublistView(section, iconOffset, iconOffset + iconLength),
    );
  }
}