import 'dart:io' as io;
import 'dart:typed_data';

import '../project.dart';

/// A single file to upload into an animation's folder on the device
/// (e.g. `meta.txt`, `frame_0.bm`).
class DolphinPackFile {
  DolphinPackFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Collects the files that make up a [PaintProject] on the device. Every
/// project is already a Flipper dolphin animation folder (`meta.txt` +
/// `frame_*.bm`), so the existing files are shipped verbatim — preserving
/// dimensions and bubble slots.
abstract final class DolphinPack {
  /// Device-safe folder name for [project]; also used as the manifest `Name:`.
  static String deviceName(PaintProject project) {
    final cleaned = project.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'_+'), '_');
    return trimmed.isEmpty ? 'animation' : trimmed;
  }

  /// Reads the animation folder's `meta.txt` + `frame_*.bm` files.
  static Future<List<DolphinPackFile>> buildFiles(PaintProject project) async {
    final out = <DolphinPackFile>[];
    final dir = io.Directory(project.path);
    final framePattern = RegExp(r'^frame_\d+\.bm$');
    await for (final e in dir.list(followLinks: false)) {
      if (e is! io.File) continue;
      final name = _baseName(e.path);
      if (name == 'meta.txt' || framePattern.hasMatch(name)) {
        out.add(DolphinPackFile(name, await e.readAsBytes()));
      }
    }
    return out;
  }

  static String _baseName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx < 0 ? norm : norm.substring(idx + 1);
  }
}
