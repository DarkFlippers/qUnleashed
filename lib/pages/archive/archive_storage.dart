import 'dart:io' as io;

import 'models/archive_category.dart';

class LocalKeyEntry {
  LocalKeyEntry({
    required this.name,
    required this.category,
    required this.extension,
    required this.subFolder,
    required this.path,
    required this.size,
  });

  final String name;
  final ArchiveCategory category;
  final String extension;
  final String subFolder;
  final String path;
  final int size;
}

class ArchiveStorage {
  ArchiveStorage();

  io.Directory get rootDir {
    final sep = io.Platform.pathSeparator;
    final base = _baseDocsDir();
    return io.Directory('${base.path}${sep}qunleashed${sep}archive');
  }

  io.Directory _baseDocsDir() {
    final sep = io.Platform.pathSeparator;
    if (io.Platform.isWindows) {
      final profile = io.Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        return io.Directory('$profile${sep}Documents');
      }
    }
    final home = io.Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return io.Directory('$home${sep}Documents');
    }
    return io.Directory.current;
  }

  String _sanitize(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  static String? normalizeDeviceName(String? raw) {
    if (raw == null) return null;
    var name = raw.trim();
    final prefix = RegExp(r'^flipper[\s_-]+', caseSensitive: false);
    name = name.replaceFirst(prefix, '').trim();
    return name.isEmpty ? null : name;
  }

  io.File _lastDeviceFile() {
    final sep = io.Platform.pathSeparator;
    return io.File('${rootDir.path}$sep.last_device');
  }

  Future<String?> readLastDeviceName() async {
    try {
      final file = _lastDeviceFile();
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLastDeviceName(String name) async {
    try {
      await rootDir.create(recursive: true);
      await _lastDeviceFile().writeAsString(name);
    } catch (_) {}
  }

  io.Directory deviceDir(String deviceName) {
    final sep = io.Platform.pathSeparator;
    return io.Directory('${rootDir.path}$sep${_sanitize(deviceName)}');
  }

  io.Directory categoryDir(
    String deviceName,
    ArchiveCategory cat, {
    String subFolder = '',
  }) {
    final sep = io.Platform.pathSeparator;
    final base = deviceDir(deviceName).path;
    final dir = cat.flipperDir.replaceAll('/', sep);
    final sub = subFolder.isEmpty ? '' : '$sep${subFolder.replaceAll('/', sep)}';
    return io.Directory('$base$sep$dir$sub');
  }

  Future<void> migrateLegacyFolders(String currentName) async {
    if (currentName.isEmpty) return;
    final root = rootDir;
    if (!await root.exists()) return;
    final target = deviceDir(currentName);
    final canonical = target.uri.toFilePath();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! io.Directory) continue;
      final base = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity.uri.toFilePath() == canonical) continue;
      final normalized = normalizeDeviceName(base);
      final isLegacyDefault = base.toLowerCase() == 'flipper';
      if (!isLegacyDefault && normalized != currentName) continue;
      await _mergeDirectory(entity, target);
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _mergeDirectory(io.Directory src, io.Directory dst) async {
    if (!await src.exists()) return;
    await dst.create(recursive: true);
    final sep = io.Platform.pathSeparator;
    await for (final entity in src.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity is io.Directory) {
        await _mergeDirectory(entity, io.Directory('${dst.path}$sep$name'));
      } else if (entity is io.File) {
        final dstFile = io.File('${dst.path}$sep$name');
        if (!await dstFile.exists()) {
          await entity.copy(dstFile.path);
        }
      }
    }
  }

  Future<void> ensureLayout(String deviceName) async {
    for (final cat in ArchiveCategory.values) {
      await categoryDir(deviceName, cat).create(recursive: true);
      for (final sub in cat.subDirs) {
        await categoryDir(deviceName, cat, subFolder: sub).create(recursive: true);
      }
    }
  }

  Future<List<LocalKeyEntry>> listAll(String deviceName) async {
    final out = <LocalKeyEntry>[];
    for (final cat in ArchiveCategory.values) {
      out.addAll(await _listCategory(deviceName, cat, subFolder: ''));
      for (final sub in cat.subDirs) {
        out.addAll(await _listCategory(deviceName, cat, subFolder: sub));
      }
    }
    return out;
  }

  Future<List<LocalKeyEntry>> _listCategory(
    String deviceName,
    ArchiveCategory cat, {
    required String subFolder,
  }) async {
    final dir = categoryDir(deviceName, cat, subFolder: subFolder);
    if (!await dir.exists()) return const [];
    final out = <LocalKeyEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! io.File) continue;
      final base = entity.uri.pathSegments.last;
      final ext = cat.matchExtension(base);
      if (ext == null) continue;
      final stat = await entity.stat();
      final name = base.substring(0, base.length - ext.length - 1);
      out.add(LocalKeyEntry(
        name: name,
        category: cat,
        extension: ext,
        subFolder: subFolder,
        path: entity.path,
        size: stat.size,
      ));
    }
    return out;
  }

  Future<io.File> saveBytes(
    String deviceName,
    ArchiveCategory cat,
    String fileName,
    List<int> bytes, {
    String subFolder = '',
  }) async {
    final dir = categoryDir(deviceName, cat, subFolder: subFolder);
    await dir.create(recursive: true);
    final sep = io.Platform.pathSeparator;
    final file = io.File('${dir.path}$sep$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<int>?> readBytes(
    String deviceName,
    ArchiveCategory cat,
    String fileName, {
    String subFolder = '',
  }) async {
    final sep = io.Platform.pathSeparator;
    final dir = categoryDir(deviceName, cat, subFolder: subFolder);
    final file = io.File('${dir.path}$sep$fileName');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> hardDelete(
    String deviceName,
    ArchiveCategory cat,
    String fileName, {
    String subFolder = '',
  }) async {
    final sep = io.Platform.pathSeparator;
    final file = io.File(
        '${categoryDir(deviceName, cat, subFolder: subFolder).path}$sep$fileName');
    if (await file.exists()) await file.delete();
  }
}
