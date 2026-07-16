import 'dart:io' as io;
import 'dart:typed_data';

import '../../../services/repository/app.dart';
import '../data/category.dart';

class LocalKeyEntry {
  LocalKeyEntry({
    required this.name,
    required this.category,
    required this.extension,
    required this.subFolder,
    required this.path,
    required this.size,
    required this.mtime,
  });

  final String name;
  final ArchiveCategory category;
  final String extension;
  final String subFolder;
  final String path;
  final int size;
  final DateTime mtime;
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

  io.File _favoritesFile(String deviceName) {
    final sep = io.Platform.pathSeparator;
    return io.File('${deviceDir(deviceName).path}$sep.favorites');
  }

  Future<Set<String>> readFavorites(String deviceName) async {
    try {
      await resolveRootDir();
      final file = _favoritesFile(deviceName);
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      return content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> writeFavorites(String deviceName, Set<String> favorites) async {
    try {
      await resolveRootDir();
      final dir = deviceDir(deviceName);
      await dir.create(recursive: true);
      await _favoritesFile(deviceName).writeAsString(favorites.join('\n'));
    } catch (_) {}
  }

  // ── Favorited apps (.fap) ────────────────────────────────────────────────

  io.File _fapFavoritesFile(String deviceName) {
    final sep = io.Platform.pathSeparator;
    return io.File('${deviceDir(deviceName).path}$sep.fap_favorites');
  }

  /// On-disk icon path mirroring the device layout, e.g.
  /// `/ext/apps/Tools/Foo.fap` → `<device>/apps/Tools/Foo.fap.icon`.
  io.File _fapIconFile(String deviceName, String remotePath) {
    const prefix = '/ext/apps/';
    final rel = remotePath.startsWith(prefix)
        ? remotePath.substring(prefix.length)
        : remotePath.split('/').where((s) => s.isNotEmpty).last;
    final parts = rel.split('/').where((s) => s.isNotEmpty).map(_sanitize);
    return io.File('${pathJoin([deviceDir(deviceName).path, 'apps', ...parts])}.icon');
  }

  /// Reads persisted fap favorites as `(path, name)` records. The file stores
  /// one entry per line as `remotePath\tname`.
  Future<List<({String path, String name})>> readFapFavorites(
    String deviceName,
  ) async {
    try {
      await resolveRootDir();
      final file = _fapFavoritesFile(deviceName);
      if (!await file.exists()) return const [];
      final out = <({String path, String name})>[];
      for (final line in (await file.readAsString()).split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final tab = trimmed.indexOf('\t');
        final path = tab >= 0 ? trimmed.substring(0, tab) : trimmed;
        final name = tab >= 0 ? trimmed.substring(tab + 1) : '';
        out.add((path: path, name: name));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeFapFavorites(
    String deviceName,
    List<({String path, String name})> entries,
  ) async {
    try {
      await resolveRootDir();
      final dir = deviceDir(deviceName);
      await dir.create(recursive: true);
      await _fapFavoritesFile(deviceName)
          .writeAsString(entries.map((e) => '${e.path}\t${e.name}').join('\n'));
    } catch (_) {}
  }

  Future<Uint8List?> readFapIcon(String deviceName, String remotePath) async {
    try {
      await resolveRootDir();
      final file = _fapIconFile(deviceName, remotePath);
      if (!await file.exists()) return null;
      return file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeFapIcon(
    String deviceName,
    String remotePath,
    List<int> bytes,
  ) async {
    try {
      await resolveRootDir();
      final file = _fapIconFile(deviceName, remotePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<void> deleteFapIcon(String deviceName, String remotePath) async {
    try {
      await resolveRootDir();
      final file = _fapIconFile(deviceName, remotePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<List<LocalKeyEntry>> listOneCategory(
    String deviceName,
    ArchiveCategory cat,
  ) async {
    await resolveRootDir();
    if (cat.recursiveSearch) {
      return _listCategoryRecursive(deviceName, cat);
    }
    final out = <LocalKeyEntry>[];
    out.addAll(await _listCategory(deviceName, cat, subFolder: ''));
    for (final sub in cat.subDirs) {
      out.addAll(await _listCategory(deviceName, cat, subFolder: sub));
    }
    return out;
  }

  Future<List<LocalKeyEntry>> listAll(String deviceName) async {
    await resolveRootDir();
    final out = <LocalKeyEntry>[];
    for (final cat in ArchiveCategory.values) {
      if (cat.recursiveSearch) {
        out.addAll(await _listCategoryRecursive(deviceName, cat));
      } else {
        out.addAll(await _listCategory(deviceName, cat, subFolder: ''));
        for (final sub in cat.subDirs) {
          out.addAll(await _listCategory(deviceName, cat, subFolder: sub));
        }
      }
    }
    return out;
  }

  Future<List<LocalKeyEntry>> _listCategoryRecursive(
    String deviceName,
    ArchiveCategory cat,
  ) async {
    final root = categoryDir(deviceName, cat);
    if (!await root.exists()) return const [];
    final out = <LocalKeyEntry>[];
    await _walkDir(root, cat, out, relPath: '');
    return out;
  }

  Future<void> _walkDir(
    io.Directory dir,
    ArchiveCategory cat,
    List<LocalKeyEntry> out, {
    required String relPath,
  }) async {
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity is io.Directory) {
        if (cat.isIgnoredSubDir(name)) continue;
        final childRelPath = relPath.isEmpty ? name : '$relPath/$name';
        await _walkDir(entity, cat, out, relPath: childRelPath);
      } else if (entity is io.File) {
        final ext = cat.matchExtension(name);
        if (ext == null) continue;
        if (cat.isIgnoredFile(name)) continue;
        final stat = await entity.stat();
        final baseName = name.substring(0, name.length - ext.length - 1);
        out.add(
          LocalKeyEntry(
            name: baseName,
            category: cat,
            extension: ext,
            subFolder: relPath,
            path: entity.path,
            size: stat.size,
            mtime: stat.modified,
          ),
        );
      }
    }
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
          mtime: stat.modified,
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
