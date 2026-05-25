import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

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
      await _storage.migrateLegacyFolders(_deviceName);
      await _storage.ensureLayout(_deviceName);
      final localEntries = await _storage.listAll(_deviceName);
      final connected = _client.isConnected;
      _keys.clear();
      for (final entry in localEntries) {
        final key = _localKey(
            entry.category, entry.name, entry.extension, entry.subFolder);
        _keys[key] = ArchiveKey(
          name: entry.name,
          category: entry.category,
          extension: entry.extension,
          subFolder: entry.subFolder,
          state: ArchiveKeyState.local,
          localSize: entry.size,
          localPath: entry.path,
        );
      }
      notifyListeners();
      if (!connected) return;
      for (final cat in ArchiveCategory.values) {
        await _verifyScope(cat, '');
        notifyListeners();
        for (final sub in cat.subDirs) {
          await _verifyScope(cat, sub);
          notifyListeners();
        }
      }
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

  Future<void> _verifyScope(ArchiveCategory cat, String subFolder) async {
    final path = subFolder.isEmpty
        ? cat.remoteDir
        : '${cat.remoteDir}/$subFolder';
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
      if (refreshError != null) {
        throw StateError(refreshError);
      }
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
    final keyId = _localKey(key.category, key.name, key.extension, key.subFolder);
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
    _keys[keyId] = key.copyWith(
      state: ArchiveKeyState.synced,
      localSize: size,
      localPath: file.path,
      remoteSize: key.remoteSize > 0 ? key.remoteSize : size,
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
