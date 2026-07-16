import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'fap_icon.dart';
import 'metadata/parser.dart';
import 'storage.dart';
import '../category.dart';
import '../../../services/repository/app.dart' as icon_repo;
import '../models/fap.dart';
import '../models/key.dart';

enum SyncPhase { checking, downloading }

class SyncProgress {
  SyncProgress({
    required this.current,
    required this.total,
    required this.fileName,
    this.phase = SyncPhase.downloading,
    this.fileProgress,
  });
  final int current;
  final int total;
  final String fileName;
  final SyncPhase phase;
  final double? fileProgress;

  double? get ratio {
    if (total == 0) return null;
    return ((current + (fileProgress ?? 0)) / total).clamp(0.0, 1.0);
  }
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
  String? _lastReadError;
  int _lastDownloadedOk = 0;
  int _lastUpToDate = 0;
  int _lastDownloadedTotal = 0;
  Set<String> _favorites = <String>{};
  List<FapFavorite> _fapFavorites = <FapFavorite>[];

  final Map<String, ArchiveKey> _keys = <String, ArchiveKey>{};

  StreamSubscription<FlipperConnectionState>? _connSub;
  StreamSubscription<Map<String, String>>? _deviceInfoSub;

  bool get loading => _loading;
  bool get syncing => _syncing;
  ArchiveSyncStatus get syncStatus => _syncStatus;
  SyncProgress? get syncProgress => _syncProgress;
  String? get lastError => _lastError;
  int get lastDownloadedOk => _lastDownloadedOk;
  int get lastUpToDate => _lastUpToDate;
  int get lastDownloadedTotal => _lastDownloadedTotal;
  String get deviceName => _deviceName;
  bool get isConnected => _client.isConnected;
  ArchiveStorage get storage => _storage;

  /// Favorited apps (`.fap`) imported from the device, shown in the favorites
  /// list alongside starred archive keys.
  List<FapFavorite> get fapFavorites => _fapFavorites;

  // Cached, lazily-rebuilt views over [_keys]. Invalidated in [notifyListeners],
  // so each view is recomputed at most once between change notifications instead
  // of re-sorting and re-filtering the whole map on every getter access (the UI
  // reads these dozens of times per frame, including during per-file sync).
  List<ArchiveKey>? _sortedCache;
  Map<ArchiveCategory, List<ArchiveKey>>? _byCategoryCache;
  List<ArchiveKey>? _deletedCache;

  static int _compareKeys(ArchiveKey a, ArchiveKey b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.subFolder.compareTo(b.subFolder);
  }

  List<ArchiveKey> get _sorted =>
      _sortedCache ??= (_keys.values.toList()..sort(_compareKeys));

  /// Local (non-deleted, on-disk) keys grouped by category in sorted order.
  Map<ArchiveCategory, List<ArchiveKey>> get _byCategory {
    final cached = _byCategoryCache;
    if (cached != null) return cached;
    final map = <ArchiveCategory, List<ArchiveKey>>{
      for (final c in ArchiveCategory.values) c: <ArchiveKey>[],
    };
    for (final k in _sorted) {
      if (k.inLocal) map[k.category]!.add(k);
    }
    return _byCategoryCache = map;
  }

  /// Sorted local keys for [cat]. The returned list is shared and must not be
  /// mutated by callers; filter/sort with copying operations instead.
  List<ArchiveKey> keysFor(ArchiveCategory cat) => _byCategory[cat]!;

  List<ArchiveKey> deletedKeys() =>
      _deletedCache ??= _sorted.where((k) => k.isDeleted).toList();

  int countFor(ArchiveCategory cat) => _byCategory[cat]!.length;
  int get deletedCount => deletedKeys().length;

  @override
  void notifyListeners() {
    _sortedCache = null;
    _byCategoryCache = null;
    _deletedCache = null;
    super.notifyListeners();
  }

  Future<void> initialize() async {
    _connSub ??= _client.connectionStream.listen(_onConnectionChange);
    _deviceInfoSub ??= _client.deviceInfoUpdates.listen(_onDeviceInfo);
    _deviceName = _client.getName() ?? '';
    if (_deviceName.isEmpty) {
      final last = await _storage.readLastDeviceName();
      if (last != null && last.isNotEmpty) {
        _deviceName = last;
      }
    }
    await refresh();
  }

  void _onDeviceInfo(Map<String, String> patch) {
    final name = patch['hardware_name'] ?? patch['device_name'];
    if (name != null) _setDeviceName(name);
  }

  void _onConnectionChange(FlipperConnectionState s) {
    final connected = s.connected && s.device != null;
    if (!connected) {
      _syncStatus = ArchiveSyncStatus.idle;
    }
    notifyListeners();
  }

  Future<void> fullSync() async {
    final hasDeviceName = await _awaitRealDeviceName();
    if (!hasDeviceName) return;
    await syncAll();
    if (!_client.isConnected) return;
    // Phase 2: after all categories are synced, restart the progress bar and
    // sync only the favorited apps. Runs even if a category sync hiccuped.
    _syncing = true;
    _syncProgress = null;
    notifyListeners();
    try {
      await _syncDeviceFavorites();
    } finally {
      _syncing = false;
      _syncProgress = null;
      notifyListeners();
    }
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
              if (item.key.trim().isNotEmpty)
                item.key.trim(): item.value.trim(),
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
    _deviceInfoSub?.cancel();
    super.dispose();
  }

  // ── Favorites ──────────────────────────────────────────────────────────────

  Future<void> _loadFavorites() async {
    if (_deviceName.isEmpty) return;
    _favorites = await _storage.readFavorites(_deviceName);
  }

  Future<void> _loadFapFavorites() async {
    if (_deviceName.isEmpty) {
      _fapFavorites = <FapFavorite>[];
      return;
    }
    final entries = await _storage.readFapFavorites(_deviceName);
    final out = <FapFavorite>[];
    for (final e in entries) {
      var icon = await _storage.readFapIcon(_deviceName, e.path);
      icon ??= await icon_repo.readFapIcon(_fapNameFromPath(e.path));
      final name = e.name.isNotEmpty ? e.name : _fapNameFromPath(e.path);
      out.add(FapFavorite(remotePath: e.path, name: name, icon: icon));
    }
    _fapFavorites = out;
  }

  static String _fapNameFromPath(String remotePath) {
    final slash = remotePath.lastIndexOf('/');
    var name = slash >= 0 ? remotePath.substring(slash + 1) : remotePath;
    if (name.toLowerCase().endsWith('.fap')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  Future<void> toggleFavorite(ArchiveKey key) async {
    final keyId = _localKey(
      key.category,
      key.name,
      key.extension,
      key.subFolder,
    );
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

  Future<void> _syncDeviceFavorites() async {
    const path = '/ext/favorites.txt';
    final bytes = await _readRemoteBytes(path, logErrors: false);
    if (bytes == null) {
      LogService.log('[Archive] $path is unavailable');
      return;
    }

    final paths = const Utf8Decoder(allowMalformed: true)
        .convert(bytes)
        .split(RegExp(r'\r?\n'))
        .map(_normalizeFavoritePath)
        .where((line) => line.isNotEmpty)
        .toSet();
    if (paths.isEmpty) return;

    final keysByRemotePath = <String, String>{
      for (final entry in _keys.entries)
        _normalizeFavoritePath(entry.value.remotePath): entry.key,
    };
    var changed = false;
    for (final path in paths) {
      final keyId = keysByRemotePath[path];
      if (keyId != null && _favorites.add(keyId)) changed = true;
    }
    if (changed) {
      await _storage.writeFavorites(_deviceName, _favorites);
      _applyFavorites();
      notifyListeners();
    }

    await _syncFapFavorites(
      paths.where((p) => p.toLowerCase().endsWith('.fap')).toList(),
    );
  }

  /// Syncs the device's favorited apps, one `.fap` at a time, surfacing each in
  /// the (restarted) progress bar. The device list is authoritative. As soon as
  /// an app is downloaded and its icon extracted, it is appended to the list and
  /// notified so it appears in the menu immediately; apps without an extractable
  /// icon still appear, using the default icon.
  Future<void> _syncFapFavorites(List<String> fapPaths) async {
    if (_deviceName.isEmpty) return;

    final cached = {for (final f in _fapFavorites) f.remotePath: f};
    final result = <FapFavorite>[];
    _fapFavorites = result;
    notifyListeners();

    for (var i = 0; i < fapPaths.length; i++) {
      final remotePath = fapPaths[i];
      _syncProgress = SyncProgress(
        current: i,
        total: fapPaths.length,
        fileName: _fapNameFromPath(remotePath),
      );
      notifyListeners();

      final appId = _fapNameFromPath(remotePath);
      final existing = cached[remotePath];
      var name = existing?.name ?? appId;
      var icon =
          existing?.icon ?? await _storage.readFapIcon(_deviceName, remotePath);

      if (icon == null) {
        icon = await icon_repo.readFapIcon(appId);
        if (icon != null) {
          await _storage.writeFapIcon(_deviceName, remotePath, icon);
        }
      }

      if (icon == null) {
        final bytes = await _readRemoteBytes(remotePath, logErrors: false);
        if (bytes != null) {
          final extracted = extractFapIcon(Uint8List.fromList(bytes));
          if (extracted != null) {
            if (extracted.name.isNotEmpty) name = extracted.name;
            icon = extracted.icon;
            if (icon != null) {
              await _storage.writeFapIcon(_deviceName, remotePath, icon);
              await icon_repo.writeFapIcon(appId, icon);
            }
          }
        }
      }

      result.add(FapFavorite(remotePath: remotePath, name: name, icon: icon));
      await _persistFapFavorites();
      notifyListeners();
    }

    _syncProgress = SyncProgress(
      current: fapPaths.length,
      total: fapPaths.length,
      fileName: '',
    );
  }

  Future<void> _persistFapFavorites() => _storage.writeFapFavorites(
    _deviceName,
    [for (final f in _fapFavorites) (path: f.remotePath, name: f.name)],
  );

  /// Starts a favorited app on the device by its full path. Returns whether the
  /// loader accepted the request; callers open the remote control on success.
  Future<bool> launchFapFavorite(FapFavorite fav) async {
    if (!_client.isConnected) return false;
    try {
      await _client.appStart(
        StartRequest(name: fav.remotePath, args: ''),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } catch (e) {
      _lastError = '$e';
      LogService.log('[Archive] launch ${fav.remotePath} failed: $e');
      return false;
    }
  }

  /// Removes a favorited app: drops it from the local list/cache and rewrites
  /// the device's favorites.txt so it does not reappear on the next sync.
  Future<void> removeFapFavorite(FapFavorite fav) async {
    _fapFavorites = _fapFavorites
        .where((f) => f.remotePath != fav.remotePath)
        .toList();
    notifyListeners();
    await _persistFapFavorites();
    unawaited(_storage.deleteFapIcon(_deviceName, fav.remotePath));
    unawaited(_removeDeviceFavorite(fav.remotePath));
  }

  Future<void> _removeDeviceFavorite(String remotePath) async {
    if (!_client.isConnected) return;
    const favPath = '/ext/favorites.txt';
    final bytes = await _readRemoteBytes(favPath, logErrors: false);
    if (bytes == null) return;
    final target = _normalizeFavoritePath(remotePath);
    final lines = const Utf8Decoder(
      allowMalformed: true,
    ).convert(bytes).split(RegExp(r'\r?\n'));
    final kept = lines
        .where(
          (l) => l.trim().isNotEmpty && _normalizeFavoritePath(l) != target,
        )
        .toList();
    final nonEmpty = lines.where((l) => l.trim().isNotEmpty).length;
    if (kept.length == nonEmpty) return; // nothing matched
    try {
      await _client.storageWriteChunked(
        favPath,
        utf8.encode(kept.isEmpty ? '' : '${kept.join('\n')}\n'),
      );
    } catch (e) {
      LogService.log('[Archive] update favorites.txt failed: $e');
    }
  }

  static String _normalizeFavoritePath(String raw) {
    var path = raw.trim().replaceAll(r'\', '/');
    if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
      path = path.substring(1, path.length - 1).trim();
    }
    while (path.contains('//')) {
      path = path.replaceAll('//', '/');
    }
    return path;
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
    final keyId = _localKey(
      key.category,
      key.name,
      key.extension,
      key.subFolder,
    );
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
          key.category,
          newName.trim(),
          key.extension,
          key.subFolder,
        );
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
          .where(
            (k) => k.category == key.category && k.subFolder == key.subFolder,
          )
          .map((k) => k.fileName)
          .toSet();
      final newName = _nextDuplicateName(key.fileName, existingNames);
      final baseName = newName.substring(
        0,
        newName.length - key.extension.length - 1,
      );
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
      final newKeyId = _localKey(
        key.category,
        baseName,
        key.extension,
        key.subFolder,
      );
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
        _fapFavorites = <FapFavorite>[];
        if (_syncStatus == ArchiveSyncStatus.syncing) {
          _syncStatus = ArchiveSyncStatus.idle;
        }
        return;
      }
      await _loadFavorites();
      await _loadFapFavorites();
      await _storage.migrateLegacyFolders(_deviceName);
      await _storage.ensureLayout(_deviceName);
      final localEntries = await _storage.listAll(_deviceName);
      final connected = _client.isConnected;
      _keys.clear();
      for (final entry in localEntries) {
        _ingestLocal(entry);
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
      final localEntries = await _storage.listOneCategory(_deviceName, cat);
      final seen = <String>{};
      for (final entry in localEntries) {
        seen.add(_ingestLocal(entry));
      }
      _keys.removeWhere((id, v) => v.category == cat && !seen.contains(id));
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
          .where(
            (e) =>
                e.value.category == category &&
                !e.value.isDeleted &&
                _needsDownload(e.value),
          )
          .map((e) => e.key)
          .toList();
      await _downloadPending(pendingIds);
      _syncStatus = _lastError == null
          ? ArchiveSyncStatus.synced
          : ArchiveSyncStatus.idle;
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
          remoteFiles.add(
            _RemoteFile(
              category: cat,
              subFolder: subFolder,
              name: name,
              extension: ext,
              size: f.size,
            ),
          );
        }
      }
      ok = true;
    } catch (e) {
      LogService.log('[Archive] list $path failed: $e');
    }
    if (!ok) return;
    _reconcileRemote(
      remoteFiles,
      (k) => k.category == cat && k.subFolder == subFolder,
    );
  }

  Future<void> _verifyCategoryRecursive(ArchiveCategory cat) async {
    final remoteFiles = <_RemoteFile>[];
    await _collectRemoteFiles(cat, cat.remoteDir, '', remoteFiles);
    _reconcileRemote(remoteFiles, (k) => k.category == cat);
  }

  /// Merges a freshly-listed set of [remoteFiles] into [_keys]: refreshes remote
  /// sizes/states for matched keys, adds remote-only keys, and marks in-scope
  /// local keys that vanished remotely as deleted (or drops them if device-only).
  void _reconcileRemote(
    List<_RemoteFile> remoteFiles,
    bool Function(ArchiveKey key) inScope,
  ) {
    final seen = <String>{};
    for (final rf in remoteFiles) {
      final keyId = _localKey(rf.category, rf.name, rf.extension, rf.subFolder);
      seen.add(keyId);
      final existing = _keys[keyId];
      if (existing != null) {
        _keys[keyId] = existing.copyWith(
          state: existing.hasLocalFile
              ? ArchiveKeyState.synced
              : ArchiveKeyState.local,
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
      if (!inScope(key)) continue;
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
            if (cat.isIgnoredSubDir(name)) continue;
            final childRelPath = relPath.isEmpty ? name : '$relPath/$name';
            await _collectRemoteFiles(
              cat,
              '$remotePath/$name',
              childRelPath,
              out,
            );
          } else {
            final ext = cat.matchExtension(name);
            if (ext == null) continue;
            if (cat.isIgnoredFile(name)) continue;
            final baseName = name.substring(0, name.length - ext.length - 1);
            out.add(
              _RemoteFile(
                category: cat,
                subFolder: relPath,
                name: baseName,
                extension: ext,
                size: f.size,
              ),
            );
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
      await _downloadPending(pendingIds);
      _syncStatus = _lastError == null
          ? ArchiveSyncStatus.synced
          : ArchiveSyncStatus.idle;
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

  Future<bool> _localMatchesRemote(ArchiveKey key) async {
    final localPath = key.localPath;
    if (localPath == null || localPath.isEmpty) return false;
    try {
      final localBytes = await io.File(localPath).readAsBytes();
      final localMd5 = md5.convert(localBytes).toString().toLowerCase();
      final batch = await _client.storageMd5sum(
        Md5sumRequest(path: key.remotePath),
        timeout: const Duration(seconds: 15),
      );
      final remoteMd5 = (batch.items.isNotEmpty ? batch.items.first.md5sum : '')
          .trim()
          .toLowerCase();
      return remoteMd5.isNotEmpty && remoteMd5 == localMd5;
    } catch (e) {
      LogService.log('[Archive] md5 check ${key.remotePath} failed: $e');
      return false;
    }
  }

  /// Downloads every pending key id in order, publishing [_syncProgress] before
  /// each file and after it completes. Shared by [syncAll] and [syncCategory].
  Future<void> _downloadPending(List<String> pendingIds) async {
    var done = 0;
    var failed = 0;
    _lastReadError = null;
    _lastDownloadedOk = 0;
    _lastUpToDate = 0;
    _lastDownloadedTotal = pendingIds.length;
    LogService.log('[Archive] checking ${pendingIds.length} candidate file(s)');
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
        phase: SyncPhase.checking,
      );
      notifyListeners();

      if (key.hasLocalFile && await _localMatchesRemote(key)) {
        _lastUpToDate++;
        done++;
        notifyListeners();
        continue;
      }

      var lastPublished = -1.0;
      void publish(double fileProgress) {
        if (fileProgress > 0 &&
            fileProgress < 1 &&
            (fileProgress - lastPublished).abs() < 0.01) {
          return;
        }
        lastPublished = fileProgress;
        _syncProgress = SyncProgress(
          current: done,
          total: pendingIds.length,
          fileName: key.fileName,
          phase: SyncPhase.downloading,
          fileProgress: fileProgress,
        );
        notifyListeners();
      }

      publish(0);
      final ok = await _downloadAndApply(keyId, key, onProgress: publish);
      if (ok) {
        _lastDownloadedOk++;
      } else {
        failed++;
      }
      done++;
      notifyListeners();
    }
    if (failed > 0) {
      final ok = pendingIds.length - failed;
      _lastError =
          'Downloaded $ok/${pendingIds.length}; $failed failed'
          '${_lastReadError == null ? '' : ': $_lastReadError'}';
      LogService.log('[Archive] $_lastError');
    }
    _syncProgress = SyncProgress(
      current: done,
      total: pendingIds.length,
      fileName: '',
    );
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
      _lastError = 'Connect a device to restore';
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

  Future<bool> _downloadAndApply(
    String keyId,
    ArchiveKey key, {
    void Function(double fileProgress)? onProgress,
  }) async {
    final bytes = await _readRemoteBytes(
      key.remotePath,
      expectedSize: key.remoteSize,
      onProgress: onProgress,
    );
    if (bytes == null) return false;
    try {
      if (key.hasLocalFile) {
        await _storage.hardDelete(
          _deviceName,
          key.category,
          key.fileName,
          subFolder: key.subFolder,
        );
      }
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
      return true;
    } catch (e) {
      _lastReadError = 'save ${key.fileName} failed: $e';
      LogService.log('[Archive] ${_lastReadError!}');
      return false;
    }
  }

  Future<List<int>?> _readRemoteBytes(
    String path, {
    bool logErrors = true,
    int expectedSize = 0,
    void Function(double progress)? onProgress,
  }) async {
    try {
      return await _client.storageReadChunked(
        path,
        expectedSize: expectedSize,
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
    } catch (e) {
      _lastReadError = 'read $path failed: $e';
      if (logErrors) {
        LogService.log('[Archive] ${_lastReadError!}');
      }
      return null;
    }
  }

  /// Inserts or replaces a key from a locally-stored file entry.
  String _ingestLocal(LocalKeyEntry entry) {
    final keyId = _localKey(
      entry.category,
      entry.name,
      entry.extension,
      entry.subFolder,
    );
    final prev = _keys[keyId];
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
      protocol: prev?.protocol,
      extra: prev?.extra,
      meta: prev?.meta,
    );
    return keyId;
  }

  String _localKey(
    ArchiveCategory cat,
    String name,
    String extension,
    String subFolder,
  ) =>
      '${cat.flipperDir}/${subFolder.isEmpty ? '' : '$subFolder/'}$name.$extension';
}
