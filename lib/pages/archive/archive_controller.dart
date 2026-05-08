import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'archive_storage.dart';
import 'models/archive_category.dart';
import 'models/archive_key.dart';

class SyncProgress {
  SyncProgress({required this.current, required this.total, required this.fileName});
  final int current;
  final int total;
  final String fileName;
}

class ArchiveController extends ChangeNotifier {
  ArchiveController({FlipperClient? client, ArchiveStorage? storage})
      : _client = client ?? FlipperOneClient().get(),
        _storage = storage ?? ArchiveStorage();

  final FlipperClient _client;
  final ArchiveStorage _storage;

  String _deviceName = 'flipper';
  bool _loading = false;
  bool _syncing = false;
  SyncProgress? _syncProgress;
  String? _lastError;
  String _query = '';

  final Map<String, ArchiveKey> _keys = <String, ArchiveKey>{};

  StreamSubscription<FlipperConnectionState>? _connSub;

  bool get loading => _loading;
  bool get syncing => _syncing;
  SyncProgress? get syncProgress => _syncProgress;
  String? get lastError => _lastError;
  String get deviceName => _deviceName;
  String get query => _query;
  bool get isConnected => _client.isConnected;
  ArchiveStorage get storage => _storage;

  List<ArchiveKey> get allKeys {
    final list = _keys.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_query.trim().isEmpty) return list;
    final q = _query.toLowerCase();
    return list.where((k) => k.name.toLowerCase().contains(q)).toList();
  }

  List<ArchiveKey> activeKeys() => allKeys.where((k) => !k.isDeleted).toList();
  List<ArchiveKey> favoriteKeys() => activeKeys().where((k) => k.favorite).toList();
  List<ArchiveKey> nonFavoriteKeys() => activeKeys().where((k) => !k.favorite).toList();

  List<ArchiveKey> keysFor(ArchiveCategory cat) =>
      activeKeys().where((k) => k.category == cat).toList();

  List<ArchiveKey> deletedKeys() => allKeys.where((k) => k.isDeleted).toList();

  int countFor(ArchiveCategory cat) => keysFor(cat).length;
  int get deletedCount => deletedKeys().length;

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    _connSub ??= _client.connectionStream.listen((_) {
      _deviceName = _client.connectedDevice?.name ?? _deviceName;
      notifyListeners();
    });
    _deviceName = _client.connectedDevice?.name ?? _deviceName;
    await refresh();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      await _storage.ensureLayout(_deviceName);
      final localEntries = await _storage.listAll(_deviceName);
      final next = <String, ArchiveKey>{};
      for (final entry in localEntries) {
        final key = _localKey(entry.category, entry.name, deleted: entry.deleted);
        next[key] = ArchiveKey(
          name: entry.name,
          category: entry.category,
          state: entry.deleted ? ArchiveKeyState.deleted : ArchiveKeyState.localOnly,
          localSize: entry.size,
          localPath: entry.path,
        );
      }
      if (_client.isConnected) {
        for (final cat in ArchiveCategory.values) {
          final remote = await _listRemote(cat);
          for (final f in remote) {
            final base = f.name;
            if (!base.toLowerCase().endsWith('.${cat.extension}')) continue;
            final name = base.substring(0, base.length - cat.extension.length - 1);
            final keyDeleted = _localKey(cat, name, deleted: true);
            final keyActive = _localKey(cat, name, deleted: false);
            final existingDeleted = next[keyDeleted];
            final existingActive = next[keyActive];
            if (existingActive != null) {
              next[keyActive] = existingActive.copyWith(
                state: ArchiveKeyState.synced,
                remoteSize: f.size,
              );
            } else if (existingDeleted != null) {
              next[keyActive] = ArchiveKey(
                name: name,
                category: cat,
                state: ArchiveKeyState.remoteOnly,
                remoteSize: f.size,
              );
            } else {
              next[keyActive] = ArchiveKey(
                name: name,
                category: cat,
                state: ArchiveKeyState.remoteOnly,
                remoteSize: f.size,
              );
            }
          }
        }
      }
      _keys
        ..clear()
        ..addAll(next);
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> syncAll() async {
    if (_syncing) return;
    if (!_client.isConnected) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final pending = activeKeys()
          .where((k) => k.state == ArchiveKeyState.remoteOnly)
          .toList();
      var done = 0;
      for (final key in pending) {
        _syncProgress = SyncProgress(
          current: done,
          total: pending.length,
          fileName: key.fileName,
        );
        notifyListeners();
        await _downloadKey(key);
        done++;
      }
      _syncProgress = SyncProgress(current: done, total: pending.length, fileName: '');
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] sync failed: $e');
    } finally {
      _syncing = false;
      _syncProgress = null;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> rememberKey(ArchiveKey key) async {
    if (!_client.isConnected) return;
    if (key.state != ArchiveKeyState.remoteOnly) return;
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
      if (!key.inLocal && _client.isConnected) {
        final bytes = await _readRemoteBytes(key.remotePath);
        if (bytes != null) {
          await _storage.saveBytes(
            _deviceName,
            key.category,
            key.fileName,
            bytes,
            deleted: true,
          );
        }
      } else if (key.inLocal && !key.isDeleted) {
        await _storage.moveToDeleted(_deviceName, key.category, key.fileName);
      }
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] delete failed: $e');
    }
    await refresh();
  }

  Future<void> restoreKey(ArchiveKey key) async {
    if (!key.isDeleted) return;
    try {
      final bytes = await _storage.readBytes(
        _deviceName,
        key.category,
        key.fileName,
        deleted: true,
      );
      if (bytes == null) return;
      await _storage.moveFromDeleted(_deviceName, key.category, key.fileName);
      if (_client.isConnected) {
        await _client.storageWriteChunked(key.remotePath, bytes);
      }
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] restore failed: $e');
    }
    await refresh();
  }

  Future<void> purgeKey(ArchiveKey key) async {
    try {
      await _storage.hardDelete(_deviceName, key.category, key.fileName,
          deleted: key.isDeleted);
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] purge failed: $e');
    }
    await refresh();
  }

  Future<List<File>> _listRemote(ArchiveCategory cat) async {
    try {
      final batch = await _client.storageList(
        ListRequest(path: cat.remoteDir),
        timeout: const Duration(seconds: 30),
      );
      final files = <File>[];
      for (final r in batch.items) {
        files.addAll(r.file.where((f) => f.type == File_FileType.FILE));
      }
      return files;
    } catch (e) {
      LogService.log('[Archive] list ${cat.remoteDir} failed: $e');
      return const [];
    }
  }

  Future<void> _downloadKey(ArchiveKey key) async {
    final bytes = await _readRemoteBytes(key.remotePath);
    if (bytes == null) return;
    await _storage.saveBytes(_deviceName, key.category, key.fileName, bytes);
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

  String _localKey(ArchiveCategory cat, String name, {required bool deleted}) =>
      '${deleted ? 'd' : 'a'}:${cat.flipperDir}/$name';
}
