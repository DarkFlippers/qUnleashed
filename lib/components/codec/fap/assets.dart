import 'dart:typed_data';
import 'readcs.dart';

const int kFapAssetsMagic = 0x4F4C5A44;
const int kFapAssetsVersion = 1;

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
      dirs.add(readCString(raw, 0) ?? '');
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
      files.add(FapAssetFile(path: readCString(raw, 0) ?? '', size: size));
    }

    return FapAssets(dirs: dirs, files: files, signature: _hex(signature));
  }
}

String _hex(Uint8List bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}