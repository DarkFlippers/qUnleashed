import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/widgets.dart';

import '../../../components/codec/fap/icon.dart';
import '../../../components/archive/parser.dart';
import '../../../components/path.dart';
import '../../../services/archive/storage.dart';
import '../../../components/archive/category.dart';
import '../../../services/progress_throttle.dart';
import '../../../services/storage/paths.dart' as icon_repo;
import '../../../services/storage/fap_icons.dart' as icon_repo;
import '../../../components/archive/models/fap.dart';
import '../../../components/archive/models/key.dart';
import '../../../services/logging.dart';

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
    required this.flipperDir,
    required this.subFolder,
    required this.name,
    required this.extension,
    required this.size,
  });
  final ArchiveCategory category;
  final String flipperDir;
  final String subFolder;
  final String name;
  final String extension;
  final int size;
}

class ArchiveController extends ChangeNotifier with WidgetsBindingObserver {
  /// [client] is the one the app resolved at its composition root.
  ///
  /// Required now. The fallback was there for `ArchivePage` building its own
  /// controller, and that page is built in one place - `AppShell`, which has
  /// the client the root handed it. ADR 0002.
  ArchiveController({required this._client, ArchiveStorage? storage})
    : _storage = storage ?? ArchiveStorage();

  final FlipperClient _client;
  final ArchiveStorage _storage;

  String _deviceName = '';
  bool _loading = false;
  bool _syncing = false;
  ArchiveSyncStatus _syncStatus = ArchiveSyncStatus.idle;
  SyncProgress? _syncProgress;
  String? _busyPath;
  double _busyProgress = 0;
  String? _lastError;
  String? _lastFailure;

  /// The last file a download could not read, folded into the sync summary
  /// below. Internal: it is not a second error field, it is one line of one.
  String? _lastReadError;

  Set<String> _favorites = <String>{};
  List<FapFavorite> _fapFavorites = <FapFavorite>[];

  final Map<String, ArchiveKey> _keys = <String, ArchiveKey>{};

  StreamSubscription<FlipperConnectionState>? _connSub;
  StreamSubscription<Map<String, String>>? _deviceInfoSub;

  bool get loading => _loading;
  bool get syncing => _syncing;
  ArchiveSyncStatus get syncStatus => _syncStatus;
  SyncProgress? get syncProgress => _syncProgress;

  /// Inline transfer progress (0..1) for [k] while it is being downloaded from
  /// the device by a single-file action, or null when it is idle. The key's
  /// file element paints a fill from this.
  double? progressForKey(ArchiveKey k) =>
      _busyPath == k.remotePath ? _busyProgress : null;

  String? get lastError => _lastError;

  /// Why the thing the user just asked for did not happen.
  ///
  /// Separate from [lastError] because their lifetimes differ, and because
  /// [lastError] has nowhere to be seen for most of what happens here: its
  /// readers are the full-sync dialog and an empty-list subtitle, and a
  /// rename or a delete that fails does not empty a list. Every one of these
  /// operations also ends in a refresh, which clears [lastError] before
  /// anything could have read it - so the failure reached nobody at all. #110.
  ///
  /// Cleared when the next operation starts, so a page reading it straight
  /// after one is reading about that one.
  String? get lastFailure => _lastFailure;
  String get deviceName => _deviceName;
  bool get isConnected => _client.isConnected;
  FlipperClient get client => _client;
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
    WidgetsBinding.instance.addObserver(this);
    _connSub ??= _client.connectionStream.listen(_onConnectionChange);
    _deviceInfoSub ??= _client.deviceInfoUpdates.listen(_onDeviceInfo);
    _deviceName = _client.getName() ?? '';
    if (_deviceName.isEmpty) await _adoptLastDeviceName();
    await refresh();
  }

  /// Falls back to the name of the last connected device, so the archive of a
  /// Flipper that is not around stays readable. Tells whether one was found.
  Future<bool> _adoptLastDeviceName() async {
    final last = await _storage.readLastDeviceName();
    if (last == null || last.isEmpty) return false;
    _deviceName = last;
    return true;
  }

  /// Rereads `.last_device` when the app comes back to the foreground without a
  /// device name: on a fresh install the first read races the storage
  /// permission the user may have just granted on the settings screen, and
  /// nothing else would tell us the archive became readable.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(guarded('[Archive] retry device name', _retryLastDeviceName));
  }

  Future<void> _retryLastDeviceName() async {
    if (_deviceName.isNotEmpty || _loading) return;
    if (await _adoptLastDeviceName()) await refresh();
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

  /// Runs [body] as one task, bound to the Flipper it starts against.
  ///
  /// Everything below is many device calls with waits between them - walking a
  /// category, checking md5s, pulling what differs, writing back - all about
  /// one Flipper's card. Bound, a sync that spans a device switch finishes on
  /// the card it was reading; unbound, it would carry on comparing one
  /// Flipper's files against another's and copy the difference between them.
  ///
  /// Not on the single-call operations: one request cannot be split across two
  /// devices, because its session is resolved once, when it is sent.
  Future<T> _task<T>(Future<T> Function() body) =>
      _client.runTask(FlipperRequestPriority.background, body);

  Future<void> fullSync() => _task(_fullSync);

  Future<void> _fullSync() async {
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
          // Ordinary, not foreground: this names the Flipper the sync is
          // about, so it has to come from the one the sync is bound to and not
          // from whichever is on screen when it answers.
          final response = await _client.deviceInfo(
            timeout: const Duration(seconds: 15),
            priority: FlipperRequestPriority.unattended,
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
      LogService.caught('[Archive] device metadata failed: $e');
      notifyListeners();
      return false;
    }
    final name = _client.getName();
    if (name == null || name.isEmpty) {
      _lastError = l10n.archiveNoHardwareName;
      LogService.info('[Archive] device metadata has no hardware name');
      notifyListeners();
      return false;
    }
    _setDeviceName(name);
    return true;
  }

  void _setDeviceName(String name) {
    if (name.isEmpty || _deviceName == name) return;
    _deviceName = name;
    unawaited(
      guarded(
        '[Archive] remember device name',
        () => _storage.writeLastDeviceName(name),
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    var name = basename(remotePath);
    if (name.toLowerCase().endsWith('.fap')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  Future<void> toggleFavorite(ArchiveKey key) =>
      _task(() => _toggleFavorite(key));

  Future<void> _toggleFavorite(ArchiveKey key) async {
    final keyId = _keyIdOf(key);
    if (_favorites.contains(keyId)) {
      _favorites.remove(keyId);
    } else {
      _favorites.add(keyId);
    }
    unawaited(
      guarded(
        '[Archive] save favourites',
        () => _storage.writeFavorites(_deviceName, _favorites),
      ),
    );
    final existing = _keys[keyId];
    if (existing != null) {
      _keys[keyId] = existing.copyWith(favorite: _favorites.contains(keyId));
    }
    notifyListeners();
  }

  Future<void> setKeysFavorite(Iterable<ArchiveKey> keys, bool favorite) =>
      _task(() => _setKeysFavorite(keys, favorite));

  Future<void> _setKeysFavorite(
    Iterable<ArchiveKey> keys,
    bool favorite,
  ) async {
    var changed = false;
    for (final key in keys) {
      final keyId = _keyIdOf(key);
      final has = _favorites.contains(keyId);
      if (favorite && !has) {
        _favorites.add(keyId);
        changed = true;
      } else if (!favorite && has) {
        _favorites.remove(keyId);
        changed = true;
      }
      final existing = _keys[keyId];
      if (existing != null) {
        _keys[keyId] = existing.copyWith(favorite: _favorites.contains(keyId));
      }
    }
    if (changed) {
      unawaited(
        guarded(
          '[Archive] save favourites',
          () => _storage.writeFavorites(_deviceName, _favorites),
        ),
      );
      notifyListeners();
    }
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
    final bytes = (await _readRemoteBytes(path)).bytes;
    if (bytes == null) {
      LogService.info('[Archive] $path is unavailable');
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
        final bytes = (await _readRemoteBytes(remotePath)).bytes;
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

  /// Paths with a launch in flight.
  ///
  /// `appStart` has a 15-second timeout and both pages that call this stay
  /// interactive throughout, so a second tap on the same card started the app
  /// twice and pushed two remote controls - which costs what `launchApp`'s own
  /// guard describes. Here rather than in each page because the two pages that
  /// launch a favourite - the archive overview and its favourites list - are
  /// handed the *same* controller, so the window covers a second tap after
  /// switching between them as well as two taps on one.
  ///
  /// Keyed on the path rather than a bare flag, for the reason the file manager
  /// keys its own on one: launching two *different* apps in quick succession is
  /// a thing a user does, and only the Flipper gets to refuse it. #244.
  final Set<String> _launchingFaps = {};

  /// Starts a favorited app on the device by its full path. Returns whether the
  /// loader accepted the request; callers open the remote control on success.
  ///
  /// Null means a launch of this path is already under way and this call did
  /// nothing: that first call owns the outcome, so a caller must report
  /// neither success nor failure for this one.
  Future<bool?> launchFapFavorite(FapFavorite fav) async {
    if (!_launchingFaps.add(fav.remotePath)) {
      // The caller shows nothing for a null, so without this the dropped tap
      // is nowhere: not on screen, and not in a log a bug report could carry.
      // It matters most when the page that asked first has since gone - then
      // nobody reports the outcome at all.
      LogService.caught(
        '[Archive] launch ${fav.remotePath} ignored, one already in flight',
      );
      return null;
    }
    try {
      return await _launchFapFavorite(fav);
    } finally {
      // Not notifyListeners: nothing on screen is drawn from this set. Cleared
      // whatever happened, so a failed launch leaves the card tappable.
      _launchingFaps.remove(fav.remotePath);
    }
  }

  Future<bool> _launchFapFavorite(FapFavorite fav) async {
    _lastFailure = null;
    if (!_client.isConnected) return false;
    try {
      await _client.appStart(
        StartRequest(name: fav.remotePath, args: ''),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } catch (e) {
      // The toast at the call site renders the reason, which is the surface
      // this used to stand in for - and §5 is why that is no longer enough on
      // its own: the reader who was missing is the developer.
      _lastError = _lastFailure = '$e';
      LogService.caught('[Archive] launch ${fav.remotePath} failed: $e');
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
    unawaited(
      guarded(
        '[Archive] delete app icon',
        () => _storage.deleteFapIcon(_deviceName, fav.remotePath),
      ),
    );
    unawaited(
      guarded(
        '[Archive] unfavourite on device',
        () => _removeDeviceFavorite(fav.remotePath),
      ),
    );
  }

  Future<void> _removeDeviceFavorite(String remotePath) async {
    if (!_client.isConnected) return;
    const favPath = '/ext/favorites.txt';
    final bytes = (await _readRemoteBytes(favPath)).bytes;
    if (bytes == null) return;
    final target = _normalizeFavoritePath(remotePath);
    final lines = const Utf8Decoder(allowMalformed: true)
        .convert(bytes)
        .split(RegExp(r'\r?\n'));
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
      // The favourite is already gone locally, so the two sides diverge
      // and the next sync brings it back. Nothing tells anyone.
      LogService.warn('[Archive] update favorites.txt failed: $e');
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

  /// Parses metadata for every deleted key, whatever its category. Backs the
  /// unified deleted table, whose Protocol column reads [ArchiveKey.protocol].
  Future<void> loadMetaForDeleted() async {
    await _parseMeta((k) => k.isDeleted);
  }

  /// Parses metadata for every starred key, whatever its category. Backs the
  /// unified favorites table, built the same way as the deleted one.
  Future<void> loadMetaForFavorites() async {
    await _parseMeta((k) => k.favorite);
  }

  Future<void> _parseMetaForCategory(ArchiveCategory cat) =>
      _parseMeta((k) => k.category == cat);

  Future<void> _parseMeta(bool Function(ArchiveKey key) test) async {
    var changed = false;
    for (final entry in _keys.entries.toList()) {
      final key = entry.value;
      if (!test(key)) continue;
      if (key.localPath == null) continue;
      if (key.meta != null) continue;
      final parsed = await parseArchiveKeyMeta(key.category, key.localPath);
      if (parsed == null) continue;
      _keys[entry.key] = key.copyWith(
        protocol: parsed.protocol ?? key.protocol,
        extra: parsed.extra ?? key.extra,
        meta: parsed.meta,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // ── Rename / Duplicate ─────────────────────────────────────────────────────

  Future<void> renameKey(ArchiveKey key, String newName) =>
      _task(() => _renameKey(key, newName));

  Future<void> _renameKey(ArchiveKey key, String newName) async {
    _lastFailure = null;
    if (newName.trim().isEmpty || newName == key.name) return;
    final keyId = _keyIdOf(key);
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
            // The local file is already renamed, and the key built below
            // copies the original's state - so it reports onDevice under a
            // name the device does not have, exactly as the duplicate does
            // further down. At the next sync the reconcile sees the device's
            // old name as a new key and the renamed one as vanished: the old
            // name returns to the listing, the new one is marked deleted.
            LogService.warn('[Archive] device rename failed: $e');
          }
        }
        final newKeyId = _localKey(
          key.flipperDir,
          newName.trim(),
          key.extension,
          key.subFolder,
        );
        _keys.remove(keyId);
        if (_favorites.contains(keyId)) {
          _favorites.remove(keyId);
          _favorites.add(newKeyId);
          unawaited(
            guarded(
              '[Archive] save favourites',
              () => _storage.writeFavorites(_deviceName, _favorites),
            ),
          );
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
          flipperDir: key.flipperDir,
        );
      }
    } catch (e) {
      _lastError = _lastFailure = '$e';
      LogService.warn('[Archive] rename failed: $e');
    }
    notifyListeners();
  }

  Future<void> duplicateKey(ArchiveKey key) => _task(() => _duplicateKey(key));

  Future<void> _duplicateKey(ArchiveKey key) async {
    _lastFailure = null;
    if (key.localPath == null) return;
    try {
      final existingNames = _keys.values
          .where(
            (k) =>
                k.category == key.category &&
                k.flipperDir == key.flipperDir &&
                k.subFolder == key.subFolder,
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
          // The local copy is already made, and the key built below copies
          // the original's state - so a duplicate of a synced key reports
          // itself onDevice when it never reached the Flipper. Not silence:
          // the UI says the opposite of what happened.
          LogService.warn('[Archive] device duplicate write failed: $e');
        }
      }
      final stat = await io.File(newLocalPath).stat();
      final newKeyId = _localKey(
        key.flipperDir,
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
        flipperDir: key.flipperDir,
      );
    } catch (e) {
      _lastError = _lastFailure = '$e';
      LogService.warn('[Archive] duplicate failed: $e');
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

  Future<void> refresh() => _task(_refresh);

  Future<void> _refresh() async {
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
        await _verifyCategory(cat);
        notifyListeners();
      }
      _applyFavorites();
    } catch (e) {
      if (_syncStatus == ArchiveSyncStatus.syncing) {
        _syncStatus = ArchiveSyncStatus.idle;
      }
      _lastError = '$e';
      LogService.caught('[Archive] refresh failed: $e');
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
      await _verifyCategory(cat);
      notifyListeners();
      _applyFavorites();
      await _parseMetaForCategory(cat);
    } catch (e) {
      _lastError = '$e';
      LogService.caught('[Archive] _refreshCategory $cat failed: $e');
    }
  }

  Future<void> syncCategory(ArchiveCategory category) =>
      _task(() => _syncCategory(category));

  Future<void> _syncCategory(ArchiveCategory category) async {
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
      LogService.caught('[Archive] syncCategory $category failed: $e');
    } finally {
      _syncing = false;
      _syncProgress = null;
      notifyListeners();
    }
  }

  /// Verifies every directory the category spans, honouring its scan mode.
  Future<void> _verifyCategory(ArchiveCategory cat) async {
    for (final dir in cat.flipperDirs) {
      if (cat.recursiveSearch) {
        await _verifyCategoryRecursive(cat, dir);
      } else {
        await _verifyScope(cat, dir, '');
        for (final sub in cat.subDirs) {
          await _verifyScope(cat, dir, sub);
        }
      }
    }
  }

  Future<void> _verifyScope(
    ArchiveCategory cat,
    String flipperDir,
    String subFolder,
  ) async {
    final remoteDir = ArchiveCategory.remoteDirOf(flipperDir);
    final path = subFolder.isEmpty ? remoteDir : '$remoteDir/$subFolder';
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
              flipperDir: flipperDir,
              subFolder: subFolder,
              name: name,
              extension: ext,
              size: f.size,
            ),
          );
        }
      }
      ok = true;
    } on FlipperRpcStorageNotExistException {
      // A directory that is not there holds no files, which is an answer and
      // not a failure: `remoteFiles` is already empty and the reconcile below
      // is correct to run on it.
      //
      // This is the ordinary state of a Flipper nobody has wardriven with -
      // `/ext/subghz/wardriving` and its `autosaved` are created by the app
      // that writes them - so the `warn` below fired on a healthy device every
      // time the category was opened. 22 of the 90 warnings the project sent
      // in its first three days were these two paths.
      //
      // It also corrects the state, **for this one status**, that the comment
      // below describes - and not in the way that comment's own case would
      // have been corrected, which is worth being exact about. There the
      // failure is a timeout and the reconcile would have put the synced keys
      // back; here the listing succeeded in saying the directory is gone, so
      // the reconcile marks the stale `local` keys `deleted` instead. The
      // visible result is the opposite of the comment's: `isDeleted` removes
      // emulate, send and plot from the sheet and offers restore, which is
      // right for a file the device says it does not have. (`onDevice` is
      // `state == synced`, so it reads false either way - the comment below
      // overstates that part.) Every other list failure on this path still
      // pays the cost the comment describes.
      ok = true;
    } catch (e) {
      // Reached only for wardriving, the one category that is not searched
      // recursively - so this guard covers two scopes, and the unguarded
      // recursive path below covers the other seven categories.
      //
      // The ok flag stops the reconcile running on a partial list, which is
      // right, but it is not a report and it is not free: _refreshCategory has
      // already re-ingested every local file as state local with no
      // remoteSize, and the reconcile is what would have put the synced ones
      // back. Skipping it leaves them local - onDevice false, so the device
      // actions disappear from the sheet, and _needsDownload false, so the
      // next sync will not restore them either. Nothing sets _lastError, so
      // syncCategory's check passes and the status still reads synced.
      LogService.warn('[Archive] list $path failed: $e');
    }
    if (!ok) return;
    final marked = _reconcileRemote(
      remoteFiles,
      (k) =>
          k.category == cat &&
          k.flipperDir == flipperDir &&
          k.subFolder == subFolder,
    );
    // Nothing is held back on this path - `ok` is false when anything was -
    // so an empty listing is the whole of the condition here. The case this
    // catches is the wardriving user whose `/ext/subghz/wardriving` has gone:
    // all of their local captures move to Deleted, and without this nothing
    // anywhere says why.
    _reportBulkDelete(
      cat,
      flipperDir,
      marked,
      scopeWasAbsent: remoteFiles.isEmpty,
    );
  }

  Future<void> _verifyCategoryRecursive(
    ArchiveCategory cat,
    String flipperDir,
  ) async {
    final remoteFiles = <_RemoteFile>[];
    final unread = <String>{};
    await _collectRemoteFiles(
      cat,
      flipperDir,
      ArchiveCategory.remoteDirOf(flipperDir),
      '',
      remoteFiles,
      unread,
    );
    if (unread.isNotEmpty) {
      // Once for the walk, however many of its directories went unread -
      // which is what the per-node line below cannot be, and the reason #111
      // would not raise it. A walk over a whole SD card has hundreds of
      // nodes, each with its own path and its own exception text, so nothing
      // coalesces and a degrading link would evict the transport fault
      // underneath it.
      LogService.warn(
        '[Archive] ${cat.name}: ${unread.length} folder(s) could not be '
        'listed, so what is in them is left as it was',
      );
    }
    final marked = _reconcileRemote(
      remoteFiles,
      (k) =>
          k.category == cat &&
          k.flipperDir == flipperDir &&
          _wasWalked(k.subFolder, unread),
    );
    _reportBulkDelete(
      cat,
      flipperDir,
      marked,
      scopeWasAbsent: remoteFiles.isEmpty && unread.isEmpty,
    );
  }

  /// Records a whole scope moving to `deleted`, which otherwise happens in
  /// silence.
  ///
  /// The per-node `ERROR_STORAGE_NOT_EXIST` is deliberately unlogged - a folder
  /// a user's apps have never written to is absence, not failure, and that is
  /// 13 of the warnings this branch removed. The **consequence** is a different
  /// thing: when the absent directory is the root of the walk, `remoteFiles` is
  /// empty, nothing is held back, and every local key under it is marked
  /// deleted. That is #109's outcome reinstated for one status code, and the
  /// argument for it is that the firmware looked and said there is no such
  /// path.
  ///
  /// It is a good argument and it is not airtight. `ERROR_STORAGE_NOT_READY` is
  /// a distinct code with its own exception, so an unmounted card does not
  /// arrive here - but FatFS answers the same no-path condition for a `path`
  /// that is a regular file, and these codes are a firmware contract this repo
  /// does not own while the app ships against forks. A fork that resolves
  /// mounts itself and answers NOT_EXIST where stock answers NOT_READY would
  /// empty a user's category on every refresh. One line, at `caught` so it
  /// survives a release build, is the difference between diagnosing that and
  /// guessing.
  ///
  /// Only when it happened: nothing local means nothing marked, which is the
  /// ordinary case the silence is for.
  ///
  /// [scopeWasAbsent] is a bool rather than the two collections it used to be
  /// derived from. Neither was read for its contents, only for `isNotEmpty`,
  /// and the two callers do not agree on what "the whole scope was absent"
  /// means - the flat path has an `ok` flag, the recursive walk has an
  /// `unread` set - so the caller that knows is the one that should say.
  void _reportBulkDelete(
    ArchiveCategory cat,
    String flipperDir,
    int marked, {
    required bool scopeWasAbsent,
  }) {
    if (marked == 0 || !scopeWasAbsent) return;
    LogService.caught(
      '[Archive] ${cat.name}: ${ArchiveCategory.remoteDirOf(flipperDir)} '
      'listed as not present, so $marked local file(s) now read as deleted',
    );
  }

  /// Whether the walk actually got to see [subFolder], so that a key in it
  /// missing from the listing means the file is gone rather than unread.
  ///
  /// A folder is walked unless its own listing failed or one above it did. A
  /// folder that is simply not there any more passes, because every folder on
  /// its path listed fine and none of them mentioned it - which is what makes
  /// deleting a whole directory on the Flipper still read as deleted here.
  ///
  /// There is a second route to the same answer, added with the
  /// `ERROR_STORAGE_NOT_EXIST` clause in [_collectRemoteFiles]: a folder whose
  /// **own** listing raised that status is not added to [unread] either, so it
  /// also passes. That is deliberate - the firmware looked and said the path is
  /// not there - and it is the one case where passing here marks files deleted
  /// on the strength of a status code rather than of a successful listing.
  /// [_reportBulkDelete] is what makes it visible when it does.
  ///
  /// The root failing puts the empty string in [unread], and then nothing is
  /// in scope at all. That is the case #109 was filed for: one `storageList`
  /// that timed out marked every key in the category deleted.
  static bool _wasWalked(String subFolder, Set<String> unread) {
    for (final path in unread) {
      if (path.isEmpty) return false;
      if (path == subFolder || subFolder.startsWith('$path/')) return false;
    }
    return true;
  }

  /// Merges a freshly-listed set of [remoteFiles] into [_keys]: refreshes remote
  /// sizes/states for matched keys, adds remote-only keys, and marks in-scope
  /// local keys that vanished remotely as deleted (or drops them if device-only).
  /// Returns how many in-scope local keys it marked deleted or dropped.
  ///
  /// Counted because the callers need it: an empty listing is indistinguishable
  /// from a listing of a directory that is not there, and in the second case
  /// this quietly moves every local key under it to `deleted`. A number here is
  /// what lets them say so once, and only when it actually happened.
  int _reconcileRemote(
    List<_RemoteFile> remoteFiles,
    bool Function(ArchiveKey key) inScope,
  ) {
    final seen = <String>{};
    for (final rf in remoteFiles) {
      final keyId = _localKey(
        rf.flipperDir,
        rf.name,
        rf.extension,
        rf.subFolder,
      );
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
          flipperDir: rf.flipperDir,
          subFolder: rf.subFolder,
          state: ArchiveKeyState.local,
          remoteSize: rf.size,
          favorite: _favorites.contains(keyId),
        );
      }
    }
    var marked = 0;
    for (final entry in _keys.entries.toList()) {
      final key = entry.value;
      if (!inScope(key)) continue;
      if (seen.contains(entry.key)) continue;
      marked++;
      if (!key.hasLocalFile) {
        _keys.remove(entry.key);
        continue;
      }
      _keys[entry.key] = key.copyWith(state: ArchiveKeyState.deleted);
    }
    return marked;
  }

  /// Walks [remotePath] and everything under it, adding what it finds to
  /// [out] and the relative path of every folder it could not read to
  /// [unread].
  ///
  /// The second one is the point: the caller reconciles what is on the device
  /// against what is on the phone, and a folder it never saw is not a folder
  /// whose files are gone.
  Future<void> _collectRemoteFiles(
    ArchiveCategory cat,
    String flipperDir,
    String remotePath,
    String relPath,
    List<_RemoteFile> out,
    Set<String> unread,
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
              flipperDir,
              '$remotePath/$name',
              childRelPath,
              out,
              unread,
            );
          } else {
            final ext = cat.matchExtension(name);
            if (ext == null) continue;
            if (cat.isIgnoredFile(name)) continue;
            final baseName = name.substring(0, name.length - ext.length - 1);
            out.add(
              _RemoteFile(
                category: cat,
                flipperDir: flipperDir,
                subFolder: relPath,
                name: baseName,
                extension: ext,
                size: f.size,
              ),
            );
          }
        }
      }
    } on FlipperRpcStorageNotExistException {
      // Not added to [unread], which is the whole of this clause: a folder
      // that is not there is not a folder whose contents are unknown, and
      // holding it back would leave the keys under it exactly as they were -
      // forever, on a device that is telling us plainly they are gone.
      //
      // The distinction this draws is the one #109 is about. A timeout says
      // nothing about what is on the card, so the walk must not conclude the
      // files were deleted. `ERROR_STORAGE_NOT_EXIST` says the opposite: the
      // firmware looked and there is no such path. Treating the two the same
      // is what put `badusb: 1 folder(s) could not be listed` in front of
      // every user with no `/ext/badusb`, 13 times in three days, and held
      // the category back each time.
      //
      // Unlogged for the same reason. The caller's per-walk `warn` counts
      // [unread], so this clause takes the summary down with it when nothing
      // was actually unreadable.
    } catch (e) {
      unread.add(relPath);
      // Stays at info, and now legitimately so: this is one node of a walk
      // over a whole SD card, with its own path and its own exception text,
      // so hundreds of them would not coalesce and would evict the transport
      // fault underneath. The bounded record is the caller's, one per walk -
      // which is what #109 unblocked. This one is the detail a talking build
      // can still name the directory with.
      LogService.info('[Archive] list $remotePath failed: $e');
    }
  }

  Future<void> syncAll() => _task(_syncAll);

  Future<void> _syncAll() async {
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
      LogService.caught('[Archive] sync failed: $e');
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
      LogService.info('[Archive] md5 check ${key.remotePath} failed: $e');
      return false;
    }
  }

  /// Downloads every pending key id in order, publishing [_syncProgress] before
  /// each file and after it completes. Shared by [syncAll] and [syncCategory].
  Future<void> _downloadPending(List<String> pendingIds) async {
    var done = 0;
    var failed = 0;
    // A bool and not the file it stopped at: that was always `done`, since
    // nothing changes `done` after the `break`, so it was a second copy of a
    // live variable that a reader had to prove could not diverge.
    var stoppedEarly = false;
    final byCause = <String, int>{};
    _lastReadError = null;
    LogService.info(
      '[Archive] checking ${pendingIds.length} candidate file(s)',
    );
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
        done++;
        notifyListeners();
        continue;
      }

      final throttle = ProgressThrottle();
      void publish(double fileProgress) {
        if (fileProgress > 0 &&
            fileProgress < 1 &&
            !throttle.shouldEmit(fileProgress)) {
          return;
        }
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
      var attempt = await _downloadAndApply(keyId, key, onProgress: publish);
      // `storageReadChunked` has no restart of its own, unlike
      // `storageWriteChunked`, so *this* read is lost. The **loop** is not,
      // and that distinction is the whole of this branch: `isLinkDropError`
      // is by its own definition the class an automatic reconnect makes whole
      // again, auto-reconnect is on with a 600ms settle, and a settle landing
      // mid-sync is ordinary on BLE. Breaking here abandoned the remaining
      // two thousand files for a fault the transport was already repairing -
      // CLAUDE.md's "a transfer restarts after the session is restored"
      // pointed backwards.
      //
      // So wait the way the write path waits, and ask for the same file
      // again; short-circuit, so a healthy read never reaches the wait. Only
      // a session that does not come back ends the sync.
      if (attempt.outcome == _Download.linkDropped &&
          await _client.waitForRpcSession(const Duration(seconds: 30))) {
        attempt = await _downloadAndApply(keyId, key, onProgress: publish);
      }
      if (attempt.outcome != _Download.saved) {
        failed++;
        // The shape of the failures, which is the diagnostic value the
        // per-file lines used to carry: one slot would report whichever
        // failure happened to be last, so a sync where forty files fail on a
        // corrupting card and the forty-first fails benignly would name the
        // benign one. Keyed on the exception, which is stable and
        // locale-independent - the rendered line is neither.
        if (attempt.error != null) {
          byCause.update('${attempt.error}', (n) => n + 1, ifAbsent: () => 1);
        }
      }
      done++;
      notifyListeners();
      // Every remaining file would now fail instantly against a dead
      // transport - 2267 outbound entries from one sync in the field, a burst
      // that overflows the SDK's envelope cache and evicts the error events
      // it was holding.
      if (attempt.outcome == _Download.linkDropped) {
        stoppedEarly = true;
        break;
      }
    }
    // Three at most. The map is bounded by the number of distinct faults,
    // which for `FlipperRpcException` is the status codes - but a
    // `FileSystemException` carries its path, so the join is capped rather
    // than the keys: this string reaches the UI.
    final causes = byCause.entries
        .take(3)
        .map((e) => '${e.key} x${e.value}')
        .join(', ');
    final tail = causes.isEmpty ? '' : ' ($causes)';
    if (stoppedEarly) {
      // Reported as an outcome and not as a ratio. `done` as the total read
      // "Downloaded 0/1; 1 failed" for a sync of two thousand files - tidy,
      // and a claim that it finished; `pendingIds.length` alone called the
      // files it never asked for "failed". Neither is what happened, so the
      // truncation gets its own sentence and the queue keeps the denominator.
      //
      // The cause tail is appended here as well, rather than the string
      // taking one example: a link drop is the case most likely to have
      // several causes behind it, and the argument above applies to it with
      // more force, not less.
      _lastError = _lastFailure =
          '${l10n.archiveSyncStoppedEarly(done, pendingIds.length)}$tail';
      // `_lastFailure` as well as `_lastError`: that is the field with
      // surfaces a refresh does not clear, which its own doc explains and
      // #110 is about. On the common path - pull to refresh, a non-empty
      // category - `_lastError` is rendered nowhere at all, so a sync that
      // stopped on a dead link would otherwise just look finished.
      LogService.warn('[Archive] $_lastError');
    } else if (failed > 0) {
      final ok = done - failed;
      _lastError =
          '${l10n.archiveDownloadedSummary(ok, pendingIds.length, failed)}'
          '$tail';
      // `warn` and not `info`, which const-folds away in release - so the one
      // line that replaces the per-file flood was the one line that did not
      // ship. §5's per-sync summary at `warn`, which #194 already settled for
      // the `md5 check` loop next door, is the precedent this follows.
      LogService.warn('[Archive] $_lastError');
    }
    _syncProgress = SyncProgress(
      current: done,
      total: pendingIds.length,
      fileName: '',
    );
  }

  Future<void> deleteKeys(
    Iterable<ArchiveKey> keys, {
    bool local = true,
    bool remote = true,
  }) => _task(() => _deleteKeys(keys, local: local, remote: remote));

  Future<void> _deleteKeys(
    Iterable<ArchiveKey> keys, {
    bool local = true,
    bool remote = true,
  }) async {
    _lastFailure = null;
    // Only the keys an action was actually asked of. A key that is already
    // deleted holds nothing on the device - purging the deleted list is local
    // by definition - and a key with no local copy has no local half to run.
    // Counted in, they read as deleted: the summary could name files nothing
    // was done to, and the denominator counted work nobody asked for.
    final queue = <({ArchiveKey key, bool device, bool phone})>[];
    for (final key in keys) {
      final device = remote && !key.isDeleted;
      final phone = local && (key.inLocal || key.localPath != null);
      if (device || phone) queue.add((key: key, device: device, phone: phone));
    }
    // Keyed on the half as well as the cause. A device delete that failed and
    // a local file that would not go are different failures, and tallying
    // them as one is what let "gone from the Flipper, still on the phone" be
    // reported as "not deleted". Counted rather than held in one slot, for
    // the reason the sync summary is: one slot held whichever key failed
    // last, so a card refusing thirty deletes and a thirty-first failing
    // benignly named the benign one.
    final byCause = <({bool device, String cause}), int>{};
    var deleted = 0;
    var failed = 0;
    var linkGone = false;
    for (final entry in queue) {
      final key = entry.key;
      if (entry.device) {
        // `isConnected` used to gate the remote call and nothing else: a link
        // that was down here - which for a bulk delete over BLE is ordinary -
        // skipped the device half in silence, deleted the local copy anyway,
        // and reported the whole thing as done. The file was still on the
        // Flipper and the next sync pulled it straight back. #373.
        //
        // Waited out before it counts as a failure, the way the sync loop
        // waits: auto-reconnect is on with a 600ms settle, and a settle
        // landing inside a delete of forty files is not a reason to abandon
        // the other thirty-nine.
        if (!linkGone && !_client.isConnected && !await _linkIsBack()) {
          linkGone = true;
        }
        if (linkGone) {
          // Nothing local for this key either: a delete asked for on both
          // sides is all of it or none of it, and the half-applied state is
          // the one that reads as success and comes back on the next sync.
          // A skip and not a break, because a key further down that needs no
          // link - a purge behind a live key - is not waiting on a transport
          // and has no reason to be abandoned with it.
          continue;
        }
        try {
          await _deleteOnDevice(key);
        } catch (e) {
          failed++;
          byCause.update(
            (device: true, cause: _groupableCause(e)),
            (n) => n + 1,
            ifAbsent: () => 1,
          );
          // The local copy stays: it is the only thing left on this phone
          // pointing at a file the device still holds.
          continue;
        }
      }
      if (!entry.phone) {
        deleted++;
        continue;
      }
      try {
        await _storage.hardDelete(
          _deviceName,
          key.category,
          key.fileName,
          flipperDir: key.flipperDir,
          subFolder: key.subFolder,
        );
        deleted++;
      } catch (e) {
        failed++;
        // #373 inverted, and the worse direction of it: the device copy is
        // gone, the local one is not, and the next upload puts the file back
        // on the card. Which half failed is in the kept line, so a report
        // says that rather than "not deleted".
        byCause.update(
          (device: false, cause: _groupableCause(e)),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    // Three, and the rest dropped. The map is bounded by the distinct faults,
    // but both of these strings are read by somebody - one on screen, one in
    // a report - and a tally of eleven is a paragraph in a toast.
    final causes = byCause.entries.take(3);
    String joined(String Function(({bool device, String cause}) k) name) =>
        causes.isEmpty
        ? ''
        : ' (${causes.map((e) => '${name(e.key)} x${e.value}').join(', ')})';
    // The user reads the cause; a report also needs to know which half of the
    // delete produced it.
    final tail = joined((k) => k.cause);
    final keptTail = joined(
      (k) => '${k.device ? 'device' : 'local'} ${k.cause}',
    );
    if (linkGone) {
      _lastError = _lastFailure =
          '${l10n.archiveDeleteStoppedEarly(deleted, queue.length)}$tail';
      // The kept line is not the localized sentence, unlike the sync summary
      // next door: a body that changes with the reader's language groups as
      // one issue per locale. It also spells out the failure count, which the
      // sentence leaves implicit in the causes. #374.
      LogService.warn(
        '[Archive] delete stopped after $deleted of ${queue.length}, '
        '$failed failed$keptTail',
      );
    } else if (failed > 0) {
      _lastError = _lastFailure =
          '${l10n.archiveDeleteSummary(failed, queue.length)}$tail';
      LogService.warn(
        '[Archive] delete: $failed of ${queue.length} failed$keptTail',
      );
    }
    await refresh();
  }

  /// Deletes [key] on the device, asking once more after a link drop.
  ///
  /// `storageDelete` has no restart of its own, unlike `storageWriteChunked`,
  /// so a drop mid-request loses this delete - though not the queue behind
  /// it. Without the retry the key the drop landed on was counted as a
  /// permanent failure while every key after it got the settle wait, which is
  /// backwards: a settle lands inside one key's request far more often than
  /// in the gap between two. `_downloadPending` gives a dropped read the same
  /// shape, against flipperlib's own definition of the fault a reconnect
  /// makes whole again.
  ///
  /// Once, not a loop: a second drop in the same breath is a link that is not
  /// settling, and the keys behind this one find that out at their own check.
  Future<void> _deleteOnDevice(ArchiveKey key) async {
    Future<void> send() => _client.storageDelete(
      DeleteRequest(path: key.remotePath, recursive: false),
      timeout: const Duration(seconds: 30),
    );
    try {
      await send();
    } catch (e) {
      if (!_client.isLinkDropError(e) || !await _linkIsBack()) rethrow;
      await send();
    }
  }

  /// Waits out a reconnect settle, answering whether the link came back.
  ///
  /// Ten seconds and not the sync loop's thirty. A sync publishes
  /// [_syncProgress] around its waits, so the screen says what is happening;
  /// nothing on the delete path publishes anything and the action stays
  /// tappable, so a long wait is an archive that looks frozen. Ten covers the
  /// 600ms settle and a reconnect that has to scan first; past that the
  /// delete reports what it managed and the user can ask again.
  ///
  /// The catch is for a promise this does not own: `waitForRpcSession` answers
  /// a timeout rather than throwing it, but it subscribes to
  /// `connectionStream` to do that, and an error there does not end that
  /// stream. A throw escaping here would abandon the queue with nothing set
  /// and nothing logged - and the sheet's `onTap` is a `VoidCallback`, so the
  /// rejection would reach the log as an unlabelled `[uncaught]` instead.
  Future<bool> _linkIsBack() async {
    try {
      return await _client.waitForRpcSession(const Duration(seconds: 10));
    } catch (e) {
      LogService.caught('[Archive] waiting for the link failed: $e');
      return false;
    }
  }

  /// [e] with whatever varies per file taken out of it.
  ///
  /// A `FileSystemException` prints the absolute path it failed on, so a
  /// tally keyed on `'$e'` holds one entry per file: it puts a path in front
  /// of the user and hands a report one issue per file instead of one per
  /// fault. The message and the OS error code are what both readers need,
  /// and neither moves with the file.
  String _groupableCause(Object e) => e is io.FileSystemException
      ? '${e.runtimeType}: ${e.message}'
            '${e.osError == null ? '' : ' (errno ${e.osError!.errorCode})'}'
      : '$e';

  /// Refuses an operation that needs the device, and records that it did.
  ///
  /// True when `isConnected` says there is no link, in which case the caller
  /// returns. The three sites in this file that did it inline told the user
  /// and told nobody else, so "restore does nothing" arrived as a bug report
  /// with no trace anywhere to read, and `caught_budget_test.dart` could not
  /// ratchet a call that did not exist. #374.
  ///
  /// `isConnected` and not `isRpcReady`, which flipperlib warns is usually
  /// the right question: `FlipperSession.callRpcFrames` switches to RPC mode
  /// itself, so the connected-but-not-yet-RPC window needs no refusal here.
  ///
  /// [what] is logged and [message] is not: the message is localized, so a
  /// line carrying it would group as one issue per language. The rate is the
  /// thing worth seeing - a burst of these means the connection state is
  /// wrong rather than the user confused.
  ///
  /// `caught` and not `warn`: pressing restore with no Flipper connected is
  /// ordinary, and there is nothing for anyone to act on.
  bool _refusedWithoutDevice(String what, String message) {
    if (_client.isConnected) return false;
    _lastError = _lastFailure = message;
    LogService.caught('[Archive] $what refused: no device connected');
    notifyListeners();
    return true;
  }

  /// Reports a restore whose local copy is not on this phone any more.
  ///
  /// [ArchiveStorage.readBytes] answers null for a file that is gone rather
  /// than throwing, so this had no catch to be reported from: the entry stayed
  /// in the deleted list, the toast never appeared - `reportArchiveFailure`
  /// returns early on a null reason - and nothing was recorded at any level.
  /// That is #374's own symptom reached by a second route, one line below the
  /// refusal the issue names.
  ///
  /// The body carries the category and not the file name: a selection of forty
  /// would otherwise be forty distinct bodies, and the category is the part
  /// that says whether one folder went missing or the archive root did.
  void _reportNoLocalCopy(ArchiveKey key) {
    _lastError = _lastFailure = l10n.archiveNoLocalCopy;
    LogService.caught(
      '[Archive] restore: no local copy in ${key.category.name}',
    );
    notifyListeners();
  }

  Future<void> restoreKey(ArchiveKey key) => _task(() => _restoreKey(key));

  Future<void> _restoreKey(ArchiveKey key) async {
    _lastFailure = null;
    if (!key.isDeleted) return;
    if (_refusedWithoutDevice('restore', l10n.archiveConnectToRestore)) return;
    try {
      final bytes = await _storage.readBytes(
        _deviceName,
        key.category,
        key.fileName,
        flipperDir: key.flipperDir,
        subFolder: key.subFolder,
      );
      if (bytes == null) {
        _reportNoLocalCopy(key);
        return;
      }
      await _client.storageWriteChunked(key.remotePath, bytes);
    } catch (e) {
      _lastError = _lastFailure = '$e';
      LogService.warn('[Archive] restore failed: $e');
    }
    await refresh();
  }

  /// Restores every deleted key in [keys] back to the device. Each key is marked
  /// as restored (and so drops out of the deleted list) the moment its own write
  /// succeeds, so the list empties one file at a time rather than all at once.
  Future<void> restoreKeys(Iterable<ArchiveKey> keys) =>
      _task(() => _restoreKeys(keys));

  Future<void> _restoreKeys(Iterable<ArchiveKey> keys) async {
    _lastFailure = null;
    // A body of its own, not the single-key path's: the two refusals are
    // indistinguishable in a report otherwise, and `LogService` folds a
    // consecutive identical body so one of them can also vanish.
    if (_refusedWithoutDevice(
      'restore selection',
      l10n.archiveConnectToRestore,
    )) {
      return;
    }
    for (final key in keys) {
      if (!key.isDeleted) continue;
      try {
        final bytes = await _storage.readBytes(
          _deviceName,
          key.category,
          key.fileName,
          flipperDir: key.flipperDir,
          subFolder: key.subFolder,
        );
        if (bytes == null) {
          _reportNoLocalCopy(key);
          continue;
        }
        await _client.storageWriteChunked(key.remotePath, bytes);
        final keyId = _keyIdOf(key);
        final existing = _keys[keyId];
        if (existing != null) {
          _keys[keyId] = existing.copyWith(
            state: existing.hasLocalFile
                ? ArchiveKeyState.synced
                : ArchiveKeyState.local,
          );
          notifyListeners();
        }
      } catch (e) {
        _lastError = _lastFailure = '$e';
        LogService.warn('[Archive] restore ${key.fileName} failed: $e');
      }
    }
    await refresh();
  }

  /// Reads one key and writes it locally.
  ///
  /// The outcome is an enum and not two bools: `ok` plus `linkDropped` had four
  /// combinations for three reachable states, and the unreachable one -
  /// landed, and the link died - had to be ruled out by reading the body.
  /// [_downloadPending] branches on all three, which is why they are named.
  Future<({_Download outcome, Object? error})> _downloadAndApply(
    String keyId,
    ArchiveKey key, {
    void Function(double fileProgress)? onProgress,
  }) async {
    final read = await _readRemoteBytes(
      key.remotePath,
      // Silent per file, and §5 has to be amended for it rather than cited
      // for it. §5 excludes the per-file `md5 check` by name on this exact
      // argument, and rules a per-file `read` the other way - into the 12
      // sites it moved *to* `caught`. That ruling predates the measurement:
      // this site alone was 94% of everything the project sent in its first
      // three days, 2267 entries from one sync, and the burst overflowed the
      // SDK's envelope cache and evicted error events. The amendment is in
      // §5's table; [_downloadPending]'s summary is what replaces this, and
      // it carries a count per cause rather than one example. The default is
      // now this, so nothing is passed here.
      expectedSize: key.remoteSize,
      onProgress: onProgress,
    );
    final bytes = read.bytes;
    if (bytes == null) {
      return (
        outcome: read.linkDropped ? _Download.linkDropped : _Download.failed,
        error: read.error,
      );
    }
    try {
      if (key.hasLocalFile) {
        await _storage.hardDelete(
          _deviceName,
          key.category,
          key.fileName,
          flipperDir: key.flipperDir,
          subFolder: key.subFolder,
        );
      }
      final file = await _storage.saveBytes(
        _deviceName,
        key.category,
        key.fileName,
        bytes,
        flipperDir: key.flipperDir,
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
      return (outcome: _Download.saved, error: null);
    } catch (e) {
      _lastReadError = l10n.archiveSaveFailed(key.fileName, '$e');
      LogService.caught('[Archive] ${_lastReadError!}');
      // A local write failed, not the link. The next file is still worth
      // asking for - a full disk is per-file, and so is a name the platform
      // refuses.
      return (outcome: _Download.failed, error: e);
    }
  }

  /// Reads [k] from the device, publishing inline per-key transfer progress so
  /// its file element renders a fill. Returns null on failure.
  Future<List<int>?> readKeyBytes(ArchiveKey k) async {
    _lastFailure = null;
    _busyPath = k.remotePath;
    _busyProgress = 0;
    notifyListeners();
    final throttle = ProgressThrottle();
    try {
      final bytes = (await _readRemoteBytes(
        k.remotePath,
        // The one read a user asked for by name, so this one is worth a line
        // of its own - which is what makes `logErrors` default to false.
        logErrors: true,
        expectedSize: k.remoteSize,
        onProgress: (p) {
          _busyProgress = p.clamp(0.0, 1.0);
          if (throttle.shouldEmit(_busyProgress)) notifyListeners();
        },
      )).bytes;
      // The reason is lifted to [lastFailure] here rather than inside
      // `_readRemoteBytes`, because this is where one thing the user asked
      // for ends. The four internal callers of that helper read a file as
      // part of something larger and recover from a miss, so a failure there
      // is not the outcome of the operation and must not be reported as one.
      if (bytes == null) _lastFailure = _lastReadError;
      return bytes;
    } finally {
      _busyPath = null;
      _busyProgress = 0;
      notifyListeners();
    }
  }

  Future<bool> writeKeyBytes(ArchiveKey k, List<int> bytes) async {
    _lastFailure = null;
    if (_refusedWithoutDevice('save', l10n.archiveConnectToSave)) return false;
    _busyPath = k.remotePath;
    _busyProgress = 0;
    notifyListeners();
    final throttle = ProgressThrottle();
    try {
      await _client.storageWriteChunked(
        k.remotePath,
        bytes,
        onProgress: (p) {
          _busyProgress = p.clamp(0.0, 1.0);
          if (throttle.shouldEmit(_busyProgress)) notifyListeners();
        },
      );
      return true;
    } catch (e) {
      // The editor renders the reason beside its own message, which is the
      // surface this used to stand in for. §5: that covers the user and not
      // the developer, and a write the device refused is the second reader's
      // business too.
      _lastError = _lastFailure = '$e';
      LogService.caught('[Archive] write ${k.remotePath} failed: $e');
      return false;
    } finally {
      _busyPath = null;
      _busyProgress = 0;
      notifyListeners();
    }
  }

  /// Downloads [k] into the share cache with inline progress and returns the
  /// local file path (for sharing), or null on failure.
  Future<String?> downloadKeyToCache(ArchiveKey k) async {
    final bytes = await readKeyBytes(k);
    if (bytes == null) return null;
    try {
      final root = await icon_repo.shareCacheDirectory();
      final dir = io.Directory(root.path);
      await dir.create(recursive: true);
      final sep = io.Platform.pathSeparator;
      final file = io.File('${dir.path}$sep${k.fileName}');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      // The half after the device: a cache directory that cannot be made or
      // a disk with no room. It threw out of here into a caller that had no
      // catch, so sharing a key on a full phone produced an unlabelled
      // [uncaught] and a share sheet that never opened. #110.
      _lastError = _lastFailure = '$e';
      LogService.warn('[Archive] cache ${k.fileName} failed: $e');
      return null;
    }
  }

  /// Reads [remotePath] for a receiver outside the app - a favourite app
  /// dragged elsewhere. Null when the read failed or [onCancel] fired first.
  Future<List<int>?> exportBytes(
    String remotePath, {
    Listenable? onCancel,
    void Function(double progress)? onProgress,
  }) async {
    var cancelled = false;
    void cancel() => cancelled = true;
    onCancel?.addListener(cancel);
    try {
      return await _client.storageReadChunked(
        remotePath,
        onProgress: onProgress,
        isCancelled: () => cancelled,
        timeout: const Duration(minutes: 5),
      );
    } on FlipperCancelledException {
      return null;
    } catch (e) {
      _lastError = _lastFailure = '$e';
      LogService.warn('[Archive] read $remotePath failed: $e');
      return null;
    } finally {
      onCancel?.removeListener(cancel);
    }
  }

  /// Reads [path] off the device, with whether a dead link is why it failed.
  ///
  /// Both halves are returned rather than one of them parked in a field. This
  /// has five callers and two of them run outside the `_task` queue -
  /// [_removeDeviceFavorite] is reached through `unawaited(guarded(...))` - so
  /// a field would belong to whoever read last, and a favourite removal
  /// landing between a failed read here and [_downloadPending]'s own check
  /// would swallow the answer. A record cannot be read by the wrong flow.
  ///
  /// [FlipperClient.isLinkDropError] is the classifier rather than a substring
  /// match: it already owns the four `StateError` spellings a dying link
  /// produces plus `FlipperTransportError`, and `storageWriteChunked` waits on
  /// the same answer before restarting an upload - which is the behaviour
  /// [_downloadPending] now mirrors, since `storageReadChunked` has no restart
  /// of its own.
  ///
  /// `error` is the exception itself and not [_lastReadError]'s rendered line.
  /// A caller that wants to group failures by cause needs something stable:
  /// the field holds a localized string, it is shared with `archiveSaveFailed`,
  /// and recovering a key by splitting it on `': '` lands on the last fragment
  /// of the message rather than on the fault. Same argument as the record
  /// itself - an answer belongs with the call that produced it.
  ///
  /// `logErrors` defaults to **false**, which is the §5 amendment written into
  /// the signature: a per-file read inside a sync is the common case and must
  /// not log, and the one read a user asked for by name opts in. Four of the
  /// five callers wanted the quiet behaviour, so the default was the minority.
  Future<({List<int>? bytes, bool linkDropped, Object? error})>
  _readRemoteBytes(
    String path, {
    bool logErrors = false,
    int expectedSize = 0,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final bytes = await _client.storageReadChunked(
        path,
        expectedSize: expectedSize,
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      return (bytes: bytes, linkDropped: false, error: null);
    } catch (e) {
      _lastReadError = l10n.archiveReadFailed(path, '$e');
      if (logErrors) {
        LogService.caught('[Archive] ${_lastReadError!}');
      }
      return (bytes: null, linkDropped: _client.isLinkDropError(e), error: e);
    }
  }

  /// Inserts or replaces a key from a locally-stored file entry.
  String _ingestLocal(LocalKeyEntry entry) {
    final keyId = _localKey(
      entry.flipperDir,
      entry.name,
      entry.extension,
      entry.subFolder,
    );
    final prev = _keys[keyId];
    _keys[keyId] = ArchiveKey(
      name: entry.name,
      category: entry.category,
      extension: entry.extension,
      flipperDir: entry.flipperDir,
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
    String flipperDir,
    String name,
    String extension,
    String subFolder,
  ) => '$flipperDir/${subFolder.isEmpty ? '' : '$subFolder/'}$name.$extension';

  String _keyIdOf(ArchiveKey key) =>
      _localKey(key.flipperDir, key.name, key.extension, key.subFolder);
}

/// What one file's download did, for [ArchiveController] alone.
///
/// Three named states rather than `ok` plus `linkDropped`, which had a fourth
/// combination that cannot happen - landed, and the link died - and so had to
/// be ruled out by reading the body rather than by the type.
///
/// The distinction [_Download.linkDropped] carries is not severity, it is
/// whose problem it is: a per-file fault means ask for the next file, a dead
/// link means stop asking. `storageReadChunked` has no restart of its own, so
/// the sync loop is where that is decided.
enum _Download {
  /// Read, written locally, and the key is `synced`.
  saved,

  /// This file did not land, and the next one is still worth asking for - a
  /// refused name, a full disk, a firmware status about this path.
  failed,

  /// The link died. Nothing else in the queue can be read until it is back.
  linkDropped,
}
