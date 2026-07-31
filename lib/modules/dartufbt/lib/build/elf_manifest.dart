import 'dart:typed_data';

import 'app_manifest.dart';
import 'icon.dart';

class ElfManifest {
  static const int magic = 0x52474448;
  static const int manifestVersion = 1;

  static Uint8List assemble({
    required FlipperApplication app,
    required int hardwareTarget,
    required int sdkVersion,
    Uint8List? icon,
  }) {
    final iconData = icon ?? Uint8List(0);
    if (iconData.length > 32) {
      throw ArgumentError(
        'Flipper app icon must be 32 bytes or less, but '
        '${iconData.length} bytes were given',
      );
    }

    final name = _ascii(app.name, 32);
    final bytes = BytesBuilder();

    final header = ByteData(14);
    header.setUint32(0, magic, Endian.little);
    header.setUint32(4, manifestVersion, Endian.little);
    header.setUint32(8, sdkVersion, Endian.little);
    header.setInt16(12, hardwareTarget, Endian.little);
    bytes.add(header.buffer.asUint8List());

    final body = ByteData(6);
    body.setInt16(0, app.stackSize, Endian.little);
    body.setUint32(2, app.versionAsInt, Endian.little);
    bytes.add(body.buffer.asUint8List());
    bytes.add(name);
    bytes.addByte(iconData.isEmpty ? 0 : 1);
    bytes.add(Uint8List(32)..setRange(0, iconData.length, iconData));

    return bytes.toBytes();
  }

  static Uint8List iconBytes(FlipperImage image) {
    if (image.width != 10 || image.height != 10) {
      throw ArgumentError(
        'Flipper app icon must be 10x10 pixels, but '
        '${image.width}x${image.height} was given',
      );
    }
    return image.data;
  }

  static Uint8List _ascii(String value, int size) {
    final out = Uint8List(size);
    for (var i = 0; i < value.length && i < size; i++) {
      out[i] = value.codeUnitAt(i) & 0x7F;
    }
    return out;
  }
}
