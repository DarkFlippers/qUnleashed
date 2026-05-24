import 'dart:io' as io;

import '../../storage/app_documents.dart';
import 'models/category.dart';

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

  static io.Directory? _cachedRoot;

  Future<io.Directory> resolveRootDir() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;
    final root = await appDocumentsDirectory();
    _cachedRoot = root;
    return root;
  }

  io.Directory get rootDir {
    final cached = _cachedRoot;
    if (cached == null) {
      throw StateError('ArchiveStorage.resolveRootDir() must be awaited first');
    }
    return cached;
  }

  String _sanitize(String input) {
    return sanitizePathSegment(input);
  }

  static String? normalizeDeviceName(String? raw) {
    return normalizeFlipperDeviceName(raw);
  }

  io.File _lastDeviceFile() {
    final sep = io.Platform.pathSeparator;
    return io.File('${rootDir.path}$sep.last_device');
  }

  Future<String?> readLastDeviceName() async {
    try {
      await resolveRootDir();
      final file = _lastDeviceFile();
      if (!await file.exists()) {
        await _migrateLegacyLastDevice(file);
      }
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLastDeviceName(String name) async {
    try {
      final root = await resolveRootDir();
      await root.create(recursive: true);
      await _lastDeviceFile().writeAsString(name);
    } catch (_) {}
  }

  Future<void> _migrateLegacyLastDevice(io.File target) async {
    final docs = await userDocumentsDirectory();
    final candidates = <io.File>[
      io.File(
        pathJoin([
          (await legacyApplicationDocumentsDirectory([
            'qunleashed',
            'archive',
          ])).path,
          '.last_device',
        ]),
      ),
      io.File(pathJoin([docs.path, 'qunleashed', 'archive', '.last_device'])),
      io.File(pathJoin([docs.path, 'qUnleashed', 'archive', '.last_device'])),
    ];
    for (final file in candidates) {
      if (!await file.exists()) continue;
      await target.parent.create(recursive: true);
      await file.copy(target.path);
      return;
    }
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
    final sub = subFolder.isEmpty
        ? ''
        : '$sep${subFolder.replaceAll('/', sep)}';
    return io.Directory('$base$sep$dir$sub');
  }

  Future<void> migrateLegacyFolders(String currentName) async {
    if (currentName.isEmpty) return;
    final root = await resolveRootDir();
    await _migrateLegacyRoot(
      await legacyApplicationDocumentsDirectory(['qunleashed', 'archive']),
      currentName,
    );
    final docs = await userDocumentsDirectory();
    await _migrateLegacyRoot(
      io.Directory(pathJoin([docs.path, 'qunleashed', 'archive'])),
      currentName,
    );
    await _migrateLegacyRoot(
      io.Directory(pathJoin([docs.path, 'qUnleashed', 'archive'])),
      currentName,
    );
    await _migrateLegacyRoot(root, currentName);
  }

  Future<void> _migrateLegacyRoot(io.Directory root, String currentName) async {
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
    await resolveRootDir();
    for (final cat in ArchiveCategory.values) {
      await categoryDir(deviceName, cat).create(recursive: true);
      for (final sub in cat.subDirs) {
        await categoryDir(
          deviceName,
          cat,
          subFolder: sub,
        ).create(recursive: true);
      }
    }
  }

  Future<List<LocalKeyEntry>> listAll(String deviceName) async {
    await resolveRootDir();
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
      if (cat.isIgnoredFile(base)) continue;
      final stat = await entity.stat();
      final name = base.substring(0, base.length - ext.length - 1);
      out.add(
        LocalKeyEntry(
          name: name,
          category: cat,
          extension: ext,
          subFolder: subFolder,
          path: entity.path,
          size: stat.size,
        ),
      );
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
    await resolveRootDir();
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
    await resolveRootDir();
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
    await resolveRootDir();
    final sep = io.Platform.pathSeparator;
    final file = io.File(
      '${categoryDir(deviceName, cat, subFolder: subFolder).path}$sep$fileName',
    );
    if (await file.exists()) await file.delete();
  }
}
