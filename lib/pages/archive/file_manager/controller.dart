import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../storage/app.dart';

class RemoteEntry {
  RemoteEntry({required this.name, required this.size, required this.isDir});

  final String name;
  final int size;
  final bool isDir;

  bool get isHidden => name.startsWith('.');
}

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

  FlipperClient get client => _client;
  String get path => _path;
  bool get loading => _loading;
  String? get error => _error;
  bool get showHidden => _showHidden;
  double get transferProgress => _transferProgress;
  String? get transferLabel => _transferLabel;

  List<RemoteEntry> get entries {
    final list = _showHidden
        ? List<RemoteEntry>.from(_entries)
        : _entries.where((e) => !e.isHidden).toList();
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  bool get canGoUp => _path.length > 1 && _path != '/';

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
