import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/repository/app.dart';

class RemoteEntry {
  RemoteEntry({required this.name, required this.size, required this.isDir});

  final String name;
  final int size;
  final bool isDir;

  bool get isHidden => name.startsWith('.');

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// How directory contents are ordered. Folders are always grouped ahead of
/// files; the mode controls ordering within each group.
enum FileSortMode { name, size, type }

enum FileViewMode { list, grid }

class FileManagerController extends ChangeNotifier {
  FileManagerController({FlipperClient? client, String initialPath = '/ext'})
    : _client = client ?? FlipperOneClient().get(),
      _path = initialPath;

  final FlipperClient _client;
  bool _disposed = false;
  String _path;
  bool _loading = false;
  String? _error;
  List<RemoteEntry> _entries = const [];
  bool _showHidden = false;
  double _transferProgress = 0;
  String? _transferLabel;
  FileSortMode _sortMode = FileSortMode.type;
  bool _sortAscending = true;
  FileViewMode _viewMode = FileViewMode.list;
  String _search = '';
  String? _lastRoot;

  FlipperClient get client => _client;
  String get path => _path;
  bool get loading => _loading;
  String? get error => _error;
  bool get showHidden => _showHidden;
  double get transferProgress => _transferProgress;
  String? get transferLabel => _transferLabel;
  FileSortMode get sortMode => _sortMode;
  bool get sortAscending => _sortAscending;
  FileViewMode get viewMode => _viewMode;
  String get search => _search;
  bool get isSearching => _search.trim().isNotEmpty;

  /// The storage root (`/ext`, `/int`, …) that the current path lives under.
  String get storageRoot {
    final trimmed = _path.startsWith('/') ? _path.substring(1) : _path;
    final slash = trimmed.indexOf('/');
    final first = slash < 0 ? trimmed : trimmed.substring(0, slash);
    return first.isEmpty ? '/' : '/$first';
  }

  int _compare(RemoteEntry a, RemoteEntry b) {
    final dir = _sortAscending ? 1 : -1;
    switch (_sortMode) {
      case FileSortMode.size:
        final c = a.size.compareTo(b.size);
        return (c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase())) *
            dir;
      case FileSortMode.type:
        final c = a.extension.compareTo(b.extension);
        return (c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase())) *
            dir;
      case FileSortMode.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase()) * dir;
    }
  }

  List<RemoteEntry> _filtered(bool Function(RemoteEntry) test) {
    final q = _search.trim().toLowerCase();
    final list = _entries.where((e) {
      if (!_showHidden && e.isHidden) return false;
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      return test(e);
    }).toList()..sort(_compare);
    return list;
  }

  /// Directories in the current folder, filtered + sorted.
  List<RemoteEntry> get folders => _filtered((e) => e.isDir);

  /// Files in the current folder, filtered + sorted.
  List<RemoteEntry> get files => _filtered((e) => !e.isDir);

  /// Folders followed by files. Retained for callers that want a flat list.
  List<RemoteEntry> get entries => [...folders, ...files];

  bool get isEmptyAfterFilter => folders.isEmpty && files.isEmpty;

  bool get canGoUp => _path.length > 1 && _path != '/';

  void setSortMode(FileSortMode mode) {
    if (_sortMode == mode) {
      _sortAscending = !_sortAscending;
    } else {
      _sortMode = mode;
      _sortAscending = true;
    }
    _notify();
  }

  void setViewMode(FileViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _notify();
  }

  void toggleViewMode() {
    _viewMode =
        _viewMode == FileViewMode.list ? FileViewMode.grid : FileViewMode.list;
    _notify();
  }

  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void toggleHidden() {
    _showHidden = !_showHidden;
    _notify();
  }

  Future<void> open(String newPath) async {
    _path = _normalize(newPath);
    await refresh();
  }

  Future<void> goUp() async {
    if (!canGoUp) return;
    final idx = _path.lastIndexOf('/');
    final parent = idx <= 0 ? '/' : _path.substring(0, idx);
    await open(parent);
  }

  String childPath(String name) {
    if (_path.endsWith('/')) return '$_path$name';
    return '$_path/$name';
  }

  Future<void> refresh() async {
    // Internal storage (`/int`) holds mostly dot-prefixed system files, so
    // reveal hidden entries automatically when first entering that root. The
    // user can still toggle them off afterwards.
    final root = storageRoot;
    if (root != _lastRoot) {
      _lastRoot = root;
      if (root == '/int') _showHidden = true;
    }
    _loading = true;
    _error = null;
    _notify();
    try {
      final batch = await _client.storageList(
        ListRequest(path: _path),
        timeout: const Duration(seconds: 30),
      );
      final out = <RemoteEntry>[];
      for (final r in batch.items) {
        for (final f in r.file) {
          out.add(
            RemoteEntry(
              name: f.name,
              size: f.size,
              isDir: f.type == File_FileType.DIR,
            ),
          );
        }
      }
      _entries = out;
    } catch (e) {
      _error = '$e';
      _entries = const [];
      LogService.log('[FileManager] list $_path failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<List<int>?> readBytes(String remotePath) async {
    try {
      final batch = await _client.storageRead(
        ReadRequest(path: remotePath),
        timeout: const Duration(minutes: 5),
      );
      final bytes = <int>[];
      for (final r in batch.items) {
        if (r.hasFile()) bytes.addAll(r.file.data);
      }
      return bytes;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] read $remotePath failed: $e');
      _notify();
      return null;
    }
  }

  Future<bool> writeBytes(String remotePath, List<int> data) async {
    _transferLabel = 'Uploading ${_basename(remotePath)}';
    _transferProgress = 0;
    _notify();
    try {
      await _client.storageWriteChunked(
        remotePath,
        data,
        onProgress: (p) {
          _transferProgress = p;
          _notify();
        },
      );
      return true;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] write $remotePath failed: $e');
      return false;
    } finally {
      _transferLabel = null;
      _transferProgress = 0;
      _notify();
    }
  }

  Future<bool> delete(String remotePath, {bool recursive = false}) async {
    try {
      await _client.storageDelete(
        DeleteRequest(path: remotePath, recursive: recursive),
        timeout: const Duration(seconds: 60),
      );
      return true;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] delete $remotePath failed: $e');
      _notify();
      return false;
    }
  }

  Future<bool> mkdir(String name) async {
    final target = childPath(name);
    try {
      await _client.storageMkdir(
        MkdirRequest(path: target),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] mkdir $target failed: $e');
      _notify();
      return false;
    }
  }

  Future<bool> launchFap(String remotePath) async {
    try {
      await _client.appStart(
        StartRequest(name: remotePath, args: ''),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } on FlipperRpcAppSystemLockedException {
      rethrow;
    } on FlipperRpcBusyException {
      rethrow;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] appStart $remotePath failed: $e');
      _notify();
      return false;
    }
  }

  Future<bool> copy(String fromPath, String toPath) async {
    final bytes = await readBytes(fromPath);
    if (bytes == null) return false;
    return writeBytes(toPath, bytes);
  }

  /// Copies a file or, for directories, the whole tree (creating folders and
  /// streaming each file). Returns false on the first failure.
  Future<bool> copyEntry(
    String fromPath,
    String toPath, {
    required bool isDir,
  }) {
    return isDir ? copyRecursive(fromPath, toPath) : copy(fromPath, toPath);
  }

  Future<bool> copyRecursive(String fromPath, String toPath) async {
    try {
      await _client.storageMkdir(
        MkdirRequest(path: toPath),
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // Destination directory may already exist; keep going.
    }
    try {
      final batch = await _client.storageList(
        ListRequest(path: fromPath),
        timeout: const Duration(seconds: 30),
      );
      for (final r in batch.items) {
        for (final f in r.file) {
          final childFrom = fromPath.endsWith('/')
              ? '$fromPath${f.name}'
              : '$fromPath/${f.name}';
          final childTo = toPath.endsWith('/')
              ? '$toPath${f.name}'
              : '$toPath/${f.name}';
          if (f.type == File_FileType.DIR) {
            if (!await copyRecursive(childFrom, childTo)) return false;
          } else {
            final bytes = await readBytes(childFrom);
            if (bytes == null) return false;
            if (!await writeBytes(childTo, bytes)) return false;
          }
        }
      }
      return true;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] copyRecursive $fromPath failed: $e');
      _notify();
      return false;
    }
  }

  Future<bool> rename(String oldPath, String newPath) async {
    try {
      await _client.storageRename(
        RenameRequest(oldPath: oldPath, newPath: newPath),
        timeout: const Duration(seconds: 30),
      );
      return true;
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] rename $oldPath failed: $e');
      _notify();
      return false;
    }
  }

  Future<String?> downloadTo(String remotePath, {String? localFolder}) async {
    final bytes = await readBytes(remotePath);
    if (bytes == null) return null;
    final dir = io.Directory(
      localFolder ?? await _defaultDownloadDir(remotePath),
    );
    await dir.create(recursive: true);
    final sep = io.Platform.pathSeparator;
    final file = io.File('${dir.path}$sep${_basename(remotePath)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Downloads [entries] from the current directory into [destDir] (files and
  /// whole directory trees, recreated recursively). A first pass enumerates the
  /// tree and sums file sizes so [transferProgress] reflects true byte-level
  /// progress across the whole batch (the read RPC streams frames, observed via
  /// [FlipperStorageApi.storageReadChunked]). Returns the number of files that
  /// failed to download.
  Future<int> downloadEntriesTo(
    List<RemoteEntry> entries, {
    required String destDir,
  }) async {
    final sep = io.Platform.pathSeparator;
    final plan = <(String remote, String local, int size)>[];
    for (final e in entries) {
      final remote = childPath(e.name);
      final local = '$destDir$sep${e.name}';
      if (e.isDir) {
        await _planDir(remote, local, plan);
      } else {
        plan.add((remote, local, e.size));
      }
    }

    final totalFiles = plan.length;
    if (totalFiles == 0) return 0;
    final totalBytes = plan.fold<int>(0, (s, p) => s + p.$3);

    _transferProgress = 0;
    _notify();

    // Throttle notifications: only repaint when progress moves ≥1% (read frames
    // are small and frequent), plus once per file for the label and at the end.
    var lastNotified = -1.0;
    void publish(double p) {
      _transferProgress = p.clamp(0.0, 1.0);
      if (_transferProgress - lastNotified >= 0.01 || _transferProgress >= 1.0) {
        lastNotified = _transferProgress;
        _notify();
      }
    }

    var doneBytes = 0;
    var doneFiles = 0;
    var failures = 0;
    try {
      for (final (remote, local, size) in plan) {
        _transferLabel =
            'Downloading ${_basename(remote)}  (${doneFiles + 1}/$totalFiles)';
        _notify();
        final base = doneBytes;
        final bytes = await _readForDownload(remote, size, (p) {
          if (totalBytes > 0) {
            publish((base + size * p) / totalBytes);
          } else {
            publish((doneFiles + p) / totalFiles);
          }
        });
        if (bytes == null) {
          failures++;
        } else {
          final file = io.File(local);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
        }
        doneBytes += size;
        doneFiles++;
        publish(totalBytes > 0 ? doneBytes / totalBytes : doneFiles / totalFiles);
      }
    } finally {
      _transferLabel = null;
      _transferProgress = 0;
      _notify();
    }
    return failures;
  }

  /// Recursively lists [remoteDir], creating local directories (so empty
  /// folders survive) and appending every file to [out] as (remote, local, size).
  Future<void> _planDir(
    String remoteDir,
    String localDir,
    List<(String, String, int)> out,
  ) async {
    final sep = io.Platform.pathSeparator;
    await io.Directory(localDir).create(recursive: true);
    try {
      final batch = await _client.storageList(
        ListRequest(path: remoteDir),
        timeout: const Duration(seconds: 30),
      );
      for (final r in batch.items) {
        for (final f in r.file) {
          final childRemote = remoteDir.endsWith('/')
              ? '$remoteDir${f.name}'
              : '$remoteDir/${f.name}';
          final childLocal = '$localDir$sep${f.name}';
          if (f.type == File_FileType.DIR) {
            await _planDir(childRemote, childLocal, out);
          } else {
            out.add((childRemote, childLocal, f.size));
          }
        }
      }
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] list $remoteDir failed: $e');
      _notify();
    }
  }

  /// Streams [remotePath] into memory, forwarding byte-level [onProgress].
  /// Returns null on failure (matching [readBytes] error handling).
  Future<List<int>?> _readForDownload(
    String remotePath,
    int expectedSize,
    void Function(double progress) onProgress,
  ) async {
    try {
      return await _client.storageReadChunked(
        remotePath,
        expectedSize: expectedSize,
        onProgress: onProgress,
      );
    } catch (e) {
      _error = '$e';
      LogService.log('[FileManager] read $remotePath failed: $e');
      _notify();
      return null;
    }
  }

  Future<bool> uploadFromLocal(String localPath, {String? targetName}) async {
    final file = io.File(localPath);
    if (!await file.exists()) {
      _error = 'Local file not found: $localPath';
      _notify();
      return false;
    }
    final bytes = await file.readAsBytes();
    final name = targetName ?? _basename(localPath.replaceAll('\\', '/'));
    return writeBytes(childPath(name), bytes);
  }

  Future<String> _defaultDownloadDir(String remotePath) async {
    final sep = io.Platform.pathSeparator;
    final relative = remotePath.startsWith('/')
        ? remotePath.substring(1)
        : remotePath;
    final parent = relative.contains('/')
        ? relative.substring(0, relative.lastIndexOf('/'))
        : '';
    final localParent = parent.replaceAll('/', sep);
    final root = await appDocumentsDirectory();
    return pathJoin([root.path, 'downloads', localParent]);
  }

  String _basename(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  String _normalize(String p) {
    if (p.isEmpty) return '/';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}
