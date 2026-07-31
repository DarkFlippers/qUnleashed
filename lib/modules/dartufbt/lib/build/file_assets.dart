import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class FileBundler {
  const FileBundler(this.assetDirs);

  static const int magic = 0x4F4C5A44;
  static const int version = 1;

  final List<Directory> assetDirs;

  void export(File target) {
    final files = <_BundleFile>[];
    final dirs = <String>[];

    for (final dir in assetDirs) {
      if (!dir.existsSync()) {
        throw Exception('Assets directory ${dir.path} does not exist');
      }
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        final relative = _relative(dir.path, entity.path);
        if (relative.isEmpty) continue;
        if (entity is File) {
          files.add(_BundleFile(relative, entity));
        } else if (entity is Directory) {
          dirs.add(relative);
        }
      }
    }

    files.sort((a, b) => a.path.compareTo(b.path));
    dirs.sort();

    final body = BytesBuilder();
    final digestInput = BytesBuilder();

    for (final dir in dirs) {
      final name = _cstring(dir);
      body.add(_u32(name.length));
      body.add(name);
      digestInput.add(name);
    }

    for (final file in files) {
      final name = _cstring(file.path);
      final content = file.file.readAsBytesSync();
      body.add(_u32(name.length));
      body.add(name);
      body.add(_u32(content.length));
      body.add(content);
      digestInput.add(name);
      digestInput.add(content);
    }

    final signature = md5.convert(digestInput.takeBytes()).bytes;

    final out = BytesBuilder();
    out.add(_u32(magic));
    out.add(_u32(version));
    out.add(_u32(dirs.length));
    out.add(_u32(files.length));
    out.add(_u32(signature.length));
    out.add(signature);
    out.add(body.takeBytes());

    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(out.takeBytes());
  }

  static String _relative(String root, String path) {
    var relative = path.startsWith(root) ? path.substring(root.length) : path;
    relative = relative.replaceAll(r'\', '/');
    while (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    return relative;
  }

  static Uint8List _cstring(String value) {
    final bytes = Uint8List(value.length + 1);
    for (var i = 0; i < value.length; i++) {
      bytes[i] = value.codeUnitAt(i) & 0x7F;
    }
    return bytes;
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}

class _BundleFile {
  const _BundleFile(this.path, this.file);

  final String path;
  final File file;
}
