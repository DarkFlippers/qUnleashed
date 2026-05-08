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

  String _deviceName = '';
  bool _loading = false;
  bool _syncing = false;
  SyncProgress? _syncProgress;
  String? _lastError;
  String _query = '';
  bool _wasConnected = false;

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
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return a.subFolder.compareTo(b.subFolder);
      });
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
    _connSub ??= _client.connectionStream.listen(_onConnectionChange);
    final live = ArchiveStorage.normalizeDeviceName(_client.connectedDevice?.name);
    _deviceName = live ?? (await _storage.readLastDeviceName()) ?? '';
    _wasConnected = _client.isConnected;
    await refresh();
    if (_client.isConnected) {
      unawaited(syncAll());
    }
  }

  void _onConnectionChange(FlipperConnectionState s) {
    final connected = s.connected && s.device != null;
    final normalized = ArchiveStorage.normalizeDeviceName(s.device?.name);
    if (normalized != null && normalized.isNotEmpty) {
      _deviceName = normalized;
      unawaited(_storage.writeLastDeviceName(normalized));
    }
    notifyListeners();
    if (connected && !_wasConnected) {
      unawaited(_autoSyncOnConnect());
    }
    _wasConnected = connected;
  }

  Future<void> _autoSyncOnConnect() async {
    await refresh();
    if (_client.isConnected) {
      await syncAll();
    }
  }

  Future<void> fullSync() async {
    await refresh();
    if (_client.isConnected) {
      await syncAll();
    }
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
      if (_deviceName.isEmpty) {
        _keys.clear();
        return;
      }
      await _storage.migrateLegacyFolders(_deviceName);
      await _storage.ensureLayout(_deviceName);
      final localEntries = await _storage.listAll(_deviceName);
      final connected = _client.isConnected;
      final defaultLocalState =
          connected ? ArchiveKeyState.deleted : ArchiveKeyState.localOnly;
      final next = <String, ArchiveKey>{};
      for (final entry in localEntries) {
        final key = _localKey(
            entry.category, entry.name, entry.extension, entry.subFolder);
        next[key] = ArchiveKey(
          name: entry.name,
          category: entry.category,
          extension: entry.extension,
          subFolder: entry.subFolder,
          state: defaultLocalState,
          localSize: entry.size,
          localPath: entry.path,
        );
      }
      if (connected) {
        for (final cat in ArchiveCategory.values) {
          await _mergeRemote(next, cat, '');
          for (final sub in cat.subDirs) {
            await _mergeRemote(next, cat, sub);
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

  Future<void> _mergeRemote(
    Map<String, ArchiveKey> next,
    ArchiveCategory cat,
    String subFolder,
  ) async {
    final remote = await _listRemote(cat, subFolder);
    for (final f in remote) {
      final base = f.name;
      final ext = cat.matchExtension(base);
      if (ext == null) continue;
      final name = base.substring(0, base.length - ext.length - 1);
      final keyId = _localKey(cat, name, ext, subFolder);
      final existing = next[keyId];
      if (existing != null) {
        next[keyId] = existing.copyWith(
          state: ArchiveKeyState.synced,
          remoteSize: f.size,
        );
      } else {
        next[keyId] = ArchiveKey(
          name: name,
          category: cat,
          extension: ext,
          subFolder: subFolder,
          state: ArchiveKeyState.remoteOnly,
          remoteSize: f.size,
        );
      }
    }
  }

  Future<void> syncAll() async {
    if (_syncing) return;
    if (!_client.isConnected) return;
    if (_deviceName.isEmpty) return;
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

  Future<List<File>> _listRemote(ArchiveCategory cat, String subFolder) async {
    final path = subFolder.isEmpty
        ? cat.remoteDir
        : '${cat.remoteDir}/$subFolder';
    try {
      final batch = await _client.storageList(
        ListRequest(path: path),
        timeout: const Duration(seconds: 30),
      );
      final files = <File>[];
      for (final r in batch.items) {
        files.addAll(r.file.where((f) => f.type == File_FileType.FILE));
      }
      return files;
    } catch (e) {
      LogService.log('[Archive] list $path failed: $e');
      return const [];
    }
  }

  Future<void> _downloadKey(ArchiveKey key) async {
    final bytes = await _readRemoteBytes(key.remotePath);
    if (bytes == null) return;
    await _storage.saveBytes(
      _deviceName,
      key.category,
      key.fileName,
      bytes,
      subFolder: key.subFolder,
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
