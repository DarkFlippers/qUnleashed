import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'metadata/parser.dart';
import 'storage.dart';
import 'models/category.dart';
import 'models/key.dart';

class SyncProgress {
  SyncProgress({
    required this.current,
    required this.total,
    required this.fileName,
  });
  final int current;
  final int total;
  final String fileName;
}

enum ArchiveSyncStatus { idle, syncing, synced }

class _RemoteFile {
  _RemoteFile({
    required this.category,
    required this.subFolder,
    required this.name,
    required this.extension,
    required this.size,
  });
  final ArchiveCategory category;
  final String subFolder;
  final String name;
  final String extension;
  final int size;
}

class ArchiveController extends ChangeNotifier {
  ArchiveController({FlipperClient? client, ArchiveStorage? storage})
      : _client = client ?? FlipperOneClient().get(),
        _storage = storage ?? ArchiveStorage();

  final FlipperClient _client;
  final ArchiveStorage _storage;

  String _deviceName = '';
  bool _loading = false;
  bool _syncing = false;
  ArchiveSyncStatus _syncStatus = ArchiveSyncStatus.idle;
  SyncProgress? _syncProgress;
  String? _lastError;
  String _query = '';
  Set<String> _favorites = <String>{};

  final Map<String, ArchiveKey> _keys = <String, ArchiveKey>{};

  StreamSubscription<FlipperConnectionState>? _connSub;
  StreamSubscription<String>? _deviceNameSub;

  bool get loading => _loading;
  bool get syncing => _syncing;
  ArchiveSyncStatus get syncStatus => _syncStatus;
  SyncProgress? get syncProgress => _syncProgress;
  String? get lastError => _lastError;
  String get deviceName => _deviceName;
  String get query => _query;
  bool get isConnected => _client.isConnected;
  ArchiveStorage get storage => _storage;

  List<ArchiveKey> get _allRaw {
    final list = _keys.values.toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return a.subFolder.compareTo(b.subFolder);
      });
    if (_query.trim().isEmpty) return list;
    final q = _query.toLowerCase();
    return list.where((k) => k.name.toLowerCase().contains(q)).toList();
  }

  List<ArchiveKey> get allKeys => _allRaw.where((k) => k.inLocal).toList();

  List<ArchiveKey> get _rootKeys =>
      allKeys.where((k) => k.subFolder.isEmpty).toList();

  List<ArchiveKey> activeKeys() => allKeys;
  List<ArchiveKey> favoriteKeys() =>
      _rootKeys.where((k) => k.favorite).toList();
  List<ArchiveKey> nonFavoriteKeys() =>
      _rootKeys.where((k) => !k.favorite).toList();

  List<ArchiveKey> keysFor(ArchiveCategory cat) =>
      allKeys.where((k) => k.category == cat).toList();

  List<ArchiveKey> deletedKeys() =>
      _allRaw.where((k) => k.isDeleted).toList();

  int countFor(ArchiveCategory cat) => keysFor(cat).length;
  int get deletedCount => deletedKeys().length;

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    _connSub ??= _client.connectionStream.listen(_onConnectionChange);
    _deviceNameSub ??= _client.deviceNameStream.listen(_onDeviceName);
    _deviceName = _client.getName() ?? '';
    if (_deviceName.isEmpty) {
      final last = await _storage.readLastDeviceName();
      if (last != null && last.isNotEmpty) {
        _deviceName = last;
      }
    }
    await refresh();
  }

  void _onDeviceName(String name) {
    _setDeviceName(name);
  }

  void _onConnectionChange(FlipperConnectionState s) {
    final connected = s.connected && s.device != null;
    if (!connected) {
      _syncStatus = ArchiveSyncStatus.idle;
    }
    notifyListeners();
  }

  Future<void> fullSync() async {
    await _awaitRealDeviceName();
    await syncAll();
  }

  Future<bool> _awaitRealDeviceName() async {
    if (!_client.isConnected) return false;
    final cachedName = _client.getName();
    if (cachedName != null && cachedName.isNotEmpty) {
      _setDeviceName(cachedName);
      return true;
    }
    try {
      await _client.awaitDeviceInfo().timeout(
        const Duration(seconds: 20),
        onTimeout: () async {
          final response = await _client.deviceInfo(
            timeout: const Duration(seconds: 15),
            priority: FlipperRequestPriority.foreground,
          );
          return {
            for (final item in response.items)
              if (item.key.trim().isNotEmpty) item.key.trim(): item.value.trim(),
          };
        },
      );
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] device metadata failed: $e');
      notifyListeners();
      return false;
    }
    final name = _client.getName();
    if (name == null || name.isEmpty) {
      _lastError = 'Device metadata does not contain hardware name';
      LogService.log('[Archive] device metadata has no hardware name');
      notifyListeners();
      return false;
    }
    _setDeviceName(name);
    return true;
  }

  void _setDeviceName(String name) {
    if (name.isEmpty || _deviceName == name) return;
    _deviceName = name;
    unawaited(_storage.writeLastDeviceName(name));
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _deviceNameSub?.cancel();
    super.dispose();
  }

  // ── Favorites ──────────────────────────────────────────────────────────────

  Future<void> _loadFavorites() async {
    if (_deviceName.isEmpty) return;
    _favorites = await _storage.readFavorites(_deviceName);
  }

  Future<void> toggleFavorite(ArchiveKey key) async {
    final keyId = _localKey(key.category, key.name, key.extension, key.subFolder);
    if (_favorites.contains(keyId)) {
      _favorites.remove(keyId);
    } else {
      _favorites.add(keyId);
    }
    unawaited(_storage.writeFavorites(_deviceName, _favorites));
    final existing = _keys[keyId];
    if (existing != null) {
      _keys[keyId] = existing.copyWith(favorite: _favorites.contains(keyId));
    }
    notifyListeners();
  }

  void _applyFavorites() {
    for (final entry in _keys.entries.toList()) {
      final isFav = _favorites.contains(entry.key);
      if (entry.value.favorite != isFav) {
        _keys[entry.key] = entry.value.copyWith(favorite: isFav);
      }
    }
  }

  // ── Metadata ───────────────────────────────────────────────────────────────

  Future<void> loadMetaForCategory(ArchiveCategory cat) async {
    await _parseMetaForCategory(cat);
  }

  Future<void> _parseMetaForCategory(ArchiveCategory cat) async {
    var changed = false;
    for (final entry in _keys.entries.toList()) {
      if (entry.value.category != cat) continue;
      if (entry.value.localPath == null) continue;
      if (entry.value.meta != null) continue;
      final parsed = await parseArchiveKeyMeta(cat, entry.value.localPath);
      if (parsed == null) continue;
      _keys[entry.key] = entry.value.copyWith(
        protocol: parsed.protocol ?? entry.value.protocol,
        extra: parsed.extra ?? entry.value.extra,
        meta: parsed.meta,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // ── Rename / Duplicate ─────────────────────────────────────────────────────

  Future<void> renameKey(ArchiveKey key, String newName) async {
    if (newName.trim().isEmpty || newName == key.name) return;
    final keyId = _localKey(key.category, key.name, key.extension, key.subFolder);
    final newFileName = '${newName.trim()}.${key.extension}';
    try {
      if (key.localPath != null) {
        final oldFile = io.File(key.localPath!);
        final sep = io.Platform.pathSeparator;
        final newLocalPath = '${oldFile.parent.path}$sep$newFileName';
        await oldFile.rename(newLocalPath);
        if (_client.isConnected && key.onDevice) {
          final newRemotePath = key.remotePath.replaceAll(
            '/${key.fileName}',
            '/$newFileName',
          );
          try {
            await _client.storageRename(
              RenameRequest(oldPath: key.remotePath, newPath: newRemotePath),
              timeout: const Duration(seconds: 15),
            );
          } catch (e) {
            LogService.log('[Archive] device rename failed: $e');
          }
        }
        final newKeyId = _localKey(
            key.category, newName.trim(), key.extension, key.subFolder);
        _keys.remove(keyId);
        if (_favorites.contains(keyId)) {
          _favorites.remove(keyId);
          _favorites.add(newKeyId);
          unawaited(_storage.writeFavorites(_deviceName, _favorites));
        }
        _keys[newKeyId] = ArchiveKey(
          name: newName.trim(),
          category: key.category,
          state: key.state,
          extension: key.extension,
          subFolder: key.subFolder,
          remoteSize: key.remoteSize,
          localSize: key.localSize,
          localPath: newLocalPath,
          favorite: _favorites.contains(newKeyId),
          protocol: key.protocol,
          extra: key.extra,
          mtime: key.mtime,
          meta: key.meta,
        );
      }
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] rename failed: $e');
    }
    notifyListeners();
  }

  Future<void> duplicateKey(ArchiveKey key) async {
    if (key.localPath == null) return;
    try {
      final existingNames = _keys.values
          .where((k) =>
              k.category == key.category && k.subFolder == key.subFolder)
          .map((k) => k.fileName)
          .toSet();
      final newName = _nextDuplicateName(key.fileName, existingNames);
      final baseName = newName.substring(0, newName.length - key.extension.length - 1);
      final sep = io.Platform.pathSeparator;
      final dir = io.File(key.localPath!).parent.path;
      final newLocalPath = '$dir$sep$newName';
      await io.File(key.localPath!).copy(newLocalPath);
      if (_client.isConnected && key.onDevice) {
        final bytes = await io.File(newLocalPath).readAsBytes();
        final newRemotePath = key.remotePath.replaceAll(
          '/${key.fileName}',
          '/$newName',
        );
        try {
          await _client.storageWriteChunked(newRemotePath, bytes);
        } catch (e) {
          LogService.log('[Archive] device duplicate write failed: $e');
        }
      }
      final stat = await io.File(newLocalPath).stat();
      final newKeyId =
          _localKey(key.category, baseName, key.extension, key.subFolder);
      _keys[newKeyId] = ArchiveKey(
        name: baseName,
        category: key.category,
        state: key.state,
        extension: key.extension,
        subFolder: key.subFolder,
        remoteSize: key.remoteSize,
        localSize: stat.size,
        localPath: newLocalPath,
        favorite: false,
        protocol: key.protocol,
        extra: key.extra,
        mtime: stat.modified,
        meta: key.meta,
      );
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] duplicate failed: $e');
    }
    notifyListeners();
  }

  String _nextDuplicateName(String fileName, Set<String> existing) {
    final dot = fileName.lastIndexOf('.');
    final base = dot >= 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot >= 0 ? fileName.substring(dot) : '';
    var i = 1;
    while (true) {
      final candidate = '$base $i$ext';
      if (!existing.contains(candidate)) return candidate;
      i++;
    }
  }

  // ── Refresh / Sync ─────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      if (_deviceName.isEmpty) {
        _keys.clear();
        if (_syncStatus == ArchiveSyncStatus.syncing) {
          _syncStatus = ArchiveSyncStatus.idle;
        }
        return;
      }
      await _loadFavorites();
      await _storage.migrateLegacyFolders(_deviceName);
      await _storage.ensureLayout(_deviceName);
      final localEntries = await _storage.listAll(_deviceName);
      final connected = _client.isConnected;
      _keys.clear();
      for (final entry in localEntries) {
        final keyId = _localKey(
            entry.category, entry.name, entry.extension, entry.subFolder);
        _keys[keyId] = ArchiveKey(
          name: entry.name,
          category: entry.category,
          extension: entry.extension,
          subFolder: entry.subFolder,
          state: ArchiveKeyState.local,
          localSize: entry.size,
          localPath: entry.path,
          favorite: _favorites.contains(keyId),
          mtime: entry.mtime,
        );
      }
      notifyListeners();
      if (!connected) return;
      for (final cat in ArchiveCategory.values) {
        if (cat.recursiveSearch) {
          await _verifyCategoryRecursive(cat);
        } else {
          await _verifyScope(cat, '');
          for (final sub in cat.subDirs) {
            await _verifyScope(cat, sub);
          }
        }
        notifyListeners();
      }
      _applyFavorites();
    } catch (e) {
      if (_syncStatus == ArchiveSyncStatus.syncing) {
        _syncStatus = ArchiveSyncStatus.idle;
      }
      _lastError = '$e';
      LogService.log('[Archive] refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshCategory(ArchiveCategory cat) async {
    _lastError = null;
    try {
      if (_deviceName.isEmpty) {
        _keys.removeWhere((_, v) => v.category == cat);
        notifyListeners();
        return;
      }
      await _storage.ensureLayout(_deviceName);
      _keys.removeWhere((_, v) => v.category == cat);
      final localEntries = await _storage.listOneCategory(_deviceName, cat);
      for (final entry in localEntries) {
        final keyId = _localKey(
            entry.category, entry.name, entry.extension, entry.subFolder);
        _keys[keyId] = ArchiveKey(
          name: entry.name,
          category: entry.category,
          extension: entry.extension,
          subFolder: entry.subFolder,
          state: ArchiveKeyState.local,
          localSize: entry.size,
          localPath: entry.path,
          favorite: _favorites.contains(keyId),
          mtime: entry.mtime,
        );
      }
      notifyListeners();
      if (!_client.isConnected) return;
      if (cat.recursiveSearch) {
        await _verifyCategoryRecursive(cat);
      } else {
        await _verifyScope(cat, '');
        for (final sub in cat.subDirs) {
          await _verifyScope(cat, sub);
        }
      }
      notifyListeners();
      _applyFavorites();
      await _parseMetaForCategory(cat);
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] _refreshCategory $cat failed: $e');
    }
  }

  Future<void> syncCategory(ArchiveCategory category) async {
    if (_syncing) return;
    if (!_client.isConnected || _deviceName.isEmpty) {
      await _refreshCategory(category);
      return;
    }
    _syncing = true;
    _syncStatus = ArchiveSyncStatus.syncing;
    _lastError = null;
    notifyListeners();
    try {
      await _awaitRealDeviceName();
      await _refreshCategory(category);
      if (_lastError != null) throw StateError(_lastError!);
      final pendingIds = _keys.entries
          .where((e) =>
              e.value.category == category &&
              !e.value.isDeleted &&
              _needsDownload(e.value))
          .map((e) => e.key)
          .toList();
      var done = 0;
      for (final keyId in pendingIds) {
        final key = _keys[keyId];
        if (key == null) {
          done++;
          continue;
        }
        _syncProgress = SyncProgress(
          current: done,
          total: pendingIds.length,
          fileName: key.fileName,
        );
        notifyListeners();
        await _downloadAndApply(keyId, key);
        done++;
        notifyListeners();
      }
      _syncProgress = SyncProgress(
        current: done,
        total: pendingIds.length,
        fileName: '',
      );
      _syncStatus = ArchiveSyncStatus.synced;
      await _parseMetaForCategory(category);
    } catch (e) {
      _syncStatus = ArchiveSyncStatus.idle;
      _lastError = '$e';
      LogService.log('[Archive] syncCategory $category failed: $e');
    } finally {
      _syncing = false;
      _syncProgress = null;
      notifyListeners();
    }
  }

  Future<void> _verifyScope(ArchiveCategory cat, String subFolder) async {
    final path =
        subFolder.isEmpty ? cat.remoteDir : '${cat.remoteDir}/$subFolder';
    final remoteFiles = <_RemoteFile>[];
    bool ok = false;
    try {
      final batch = await _client.storageList(
        ListRequest(path: path),
        timeout: const Duration(seconds: 30),
      );
      for (final r in batch.items) {
        for (final f in r.file) {
          if (f.type != File_FileType.FILE) continue;
          final base = f.name;
          final ext = cat.matchExtension(base);
          if (ext == null) continue;
          if (cat.isIgnoredFile(base)) continue;
          final name = base.substring(0, base.length - ext.length - 1);
          remoteFiles.add(_RemoteFile(
            category: cat,
            subFolder: subFolder,
            name: name,
            extension: ext,
            size: f.size,
          ));
        }
      }
      ok = true;
    } catch (e) {
      LogService.log('[Archive] list $path failed: $e');
    }
    if (!ok) return;

    final seen = <String>{};
    for (final rf in remoteFiles) {
      final keyId =
          _localKey(rf.category, rf.name, rf.extension, rf.subFolder);
      seen.add(keyId);
      final existing = _keys[keyId];
      if (existing != null) {
        _keys[keyId] = existing.copyWith(
          state: ArchiveKeyState.local,
          remoteSize: rf.size,
        );
      } else {
        _keys[keyId] = ArchiveKey(
          name: rf.name,
          category: rf.category,
          extension: rf.extension,
          subFolder: rf.subFolder,
          state: ArchiveKeyState.local,
          remoteSize: rf.size,
          favorite: _favorites.contains(keyId),
        );
      }
    }
    for (final entry in _keys.entries.toList()) {
      final key = entry.value;
      if (key.category != cat || key.subFolder != subFolder) continue;
      if (seen.contains(entry.key)) continue;
      if (!key.hasLocalFile) {
        _keys.remove(entry.key);
        continue;
      }
      _keys[entry.key] = key.copyWith(state: ArchiveKeyState.deleted);
    }
  }

  Future<void> _verifyCategoryRecursive(ArchiveCategory cat) async {
    final remoteFiles = <_RemoteFile>[];
    await _collectRemoteFiles(cat, cat.remoteDir, '', remoteFiles);

    final seen = <String>{};
    for (final rf in remoteFiles) {
      final keyId = _localKey(rf.category, rf.name, rf.extension, rf.subFolder);
      seen.add(keyId);
      final existing = _keys[keyId];
      if (existing != null) {
        _keys[keyId] = existing.copyWith(
          state: ArchiveKeyState.local,
          remoteSize: rf.size,
        );
      } else {
        _keys[keyId] = ArchiveKey(
          name: rf.name,
          category: rf.category,
          extension: rf.extension,
          subFolder: rf.subFolder,
          state: ArchiveKeyState.local,
          remoteSize: rf.size,
          favorite: _favorites.contains(keyId),
        );
      }
    }
    for (final entry in _keys.entries.toList()) {
      final key = entry.value;
      if (key.category != cat) continue;
      if (seen.contains(entry.key)) continue;
      if (!key.hasLocalFile) {
        _keys.remove(entry.key);
        continue;
      }
      _keys[entry.key] = key.copyWith(state: ArchiveKeyState.deleted);
    }
  }

  Future<void> _collectRemoteFiles(
    ArchiveCategory cat,
    String remotePath,
    String relPath,
    List<_RemoteFile> out,
  ) async {
    try {
      final batch = await _client.storageList(
        ListRequest(path: remotePath),
        timeout: const Duration(seconds: 30),
      );
      for (final r in batch.items) {
        for (final f in r.file) {
          final name = f.name;
          if (f.type == File_FileType.DIR) {
            if (ArchiveCategory.isIgnoredSubDir(name)) continue;
            final childRelPath = relPath.isEmpty ? name : '$relPath/$name';
            await _collectRemoteFiles(cat, '$remotePath/$name', childRelPath, out);
          } else {
            final ext = cat.matchExtension(name);
            if (ext == null) continue;
            if (cat.isIgnoredFile(name)) continue;
            final baseName = name.substring(0, name.length - ext.length - 1);
            out.add(_RemoteFile(
              category: cat,
              subFolder: relPath,
              name: baseName,
              extension: ext,
              size: f.size,
            ));
          }
        }
      }
    } catch (e) {
      LogService.log('[Archive] list $remotePath failed: $e');
    }
  }

  Future<void> syncAll() async {
    if (_syncing) return;
    if (!_client.isConnected || _deviceName.isEmpty) {
      if (_syncStatus == ArchiveSyncStatus.syncing) {
        _syncStatus = ArchiveSyncStatus.idle;
        notifyListeners();
      }
      return;
    }
    _syncing = true;
    _syncStatus = ArchiveSyncStatus.syncing;
    _lastError = null;
    notifyListeners();
    try {
      await refresh();
      final refreshError = _lastError;
      if (refreshError != null) throw StateError(refreshError);
      final pendingIds = _keys.entries
          .where((e) => !e.value.isDeleted && _needsDownload(e.value))
          .map((e) => e.key)
          .toList();
      var done = 0;
      for (final keyId in pendingIds) {
        final key = _keys[keyId];
        if (key == null) {
          done++;
          continue;
        }
        _syncProgress = SyncProgress(
          current: done,
          total: pendingIds.length,
          fileName: key.fileName,
        );
        notifyListeners();
        await _downloadAndApply(keyId, key);
        done++;
        notifyListeners();
      }
      _syncProgress = SyncProgress(
        current: done,
        total: pendingIds.length,
        fileName: '',
      );
      _syncStatus = ArchiveSyncStatus.synced;
    } catch (e) {
      _syncStatus = ArchiveSyncStatus.idle;
      _lastError = '$e';
      LogService.log('[Archive] sync failed: $e');
    } finally {
      _syncing = false;
      _syncProgress = null;
      notifyListeners();
    }
  }

  bool _needsDownload(ArchiveKey k) => k.remoteSize > 0;

  Future<void> rememberKey(ArchiveKey key) async {
    if (!_client.isConnected) return;
    if (!_needsDownload(key)) return;
    try {
      await _downloadKey(key);
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] remember failed: $e');
    }
    await refresh();
  }

  Future<void> deleteKey(ArchiveKey key) async {
    try {
      if (_client.isConnected && key.onDevice) {
        await _client.storageDelete(
          DeleteRequest(path: key.remotePath, recursive: false),
          timeout: const Duration(seconds: 30),
        );
      }
      if (key.inLocal || key.localPath != null) {
        await _storage.hardDelete(
          _deviceName,
          key.category,
          key.fileName,
          subFolder: key.subFolder,
        );
      }
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] delete failed: $e');
    }
    await refresh();
  }

  Future<void> restoreKey(ArchiveKey key) async {
    if (!key.isDeleted) return;
    if (!_client.isConnected) {
      _lastError = 'Connect a Flipper to restore';
      notifyListeners();
      return;
    }
    try {
      final bytes = await _storage.readBytes(
        _deviceName,
        key.category,
        key.fileName,
        subFolder: key.subFolder,
      );
      if (bytes == null) return;
      await _client.storageWriteChunked(key.remotePath, bytes);
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] restore failed: $e');
    }
    await refresh();
  }

  Future<void> _downloadKey(ArchiveKey key) async {
    final keyId =
        _localKey(key.category, key.name, key.extension, key.subFolder);
    await _downloadAndApply(keyId, key);
  }

  Future<void> _downloadAndApply(String keyId, ArchiveKey key) async {
    if (key.hasLocalFile) {
      await _storage.hardDelete(
        _deviceName,
        key.category,
        key.fileName,
        subFolder: key.subFolder,
      );
    }
    final bytes = await _readRemoteBytes(key.remotePath);
    if (bytes == null) return;
    final file = await _storage.saveBytes(
      _deviceName,
      key.category,
      key.fileName,
      bytes,
      subFolder: key.subFolder,
    );
    final size = await file.length();
    final stat = await file.stat();
    _keys[keyId] = key.copyWith(
      state: ArchiveKeyState.synced,
      localSize: size,
      localPath: file.path,
      remoteSize: key.remoteSize > 0 ? key.remoteSize : size,
      mtime: stat.modified,
    );
  }

  Future<List<int>?> _readRemoteBytes(String path) async {
    try {
      final batch = await _client.storageRead(
        ReadRequest(path: path),
        timeout: const Duration(minutes: 2),
      );
      final bytes = <int>[];
      for (final r in batch.items) {
        if (r.hasFile()) bytes.addAll(r.file.data);
      }
      return bytes;
    } catch (e) {
      LogService.log('[Archive] read $path failed: $e');
      return null;
    }
  }

  String _localKey(
    ArchiveCategory cat,
    String name,
    String extension,
    String subFolder,
  ) =>
      '${cat.flipperDir}/${subFolder.isEmpty ? '' : '$subFolder/'}$name.$extension';
}
