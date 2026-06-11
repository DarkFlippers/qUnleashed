import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/repository/app.dart';
import '../project.dart';
import '../virtual_display_session.dart';

/// Remote dolphin directory on the Flipper SD card.
const String kDeviceDolphinPath = '/ext/dolphin';

/// Backs the Pixel Draw project manager: lists all local projects (drawings,
/// GIFs, dolphin animations and drafts) and can import the device's dolphin
/// animations into the local library.
class ProjectManagerController extends ChangeNotifier {
  ProjectManagerController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _connSub = _client.connectionStream.listen((_) => _notify());
    VirtualDisplaySession.instance.enter();
  }

  final FlipperClient _client;
  StreamSubscription<FlipperConnectionState>? _connSub;
  bool _disposed = false;

  List<PaintProject> _projects = const [];
  bool _loading = false;
  bool _importing = false;
  double? _importProgress;
  String? _importStatus;
  String? _selectedId;
  String? _error;


  List<PaintProject> get projects => _projects;
  bool get loading => _loading;
  bool get importing => _importing;
  double? get importProgress => _importProgress;
  String? get importStatus => _importStatus;
  String? get error => _error;
  bool get isConnected => _client.isConnected;
  String? get selectedId => _selectedId;


  void select(String? id) {
    _selectedId = (_selectedId == id) ? null : id;
    _notify();
    _updateDevicePreview();
  }

  int _previewToken = 0;

  Future<void> _updateDevicePreview() async {
    final token = ++_previewToken;
    final id = _selectedId;
    if (id == null) {
      VirtualDisplaySession.instance.clearPreview();
      return;
    }
    PaintProject? project;
    for (final p in _projects) {
      if (p.id == id) {
        project = p;
        break;
      }
    }
    if (project == null) {
      VirtualDisplaySession.instance.clearPreview();
      return;
    }
    try {
      final preview = await project.loadDevicePreview();
      if (token != _previewToken || _disposed) return;
      VirtualDisplaySession.instance.setPreview(preview.frames, preview.delayMs);
    } catch (_) {}
  }

  /// Scans the local library into [projects]. When [silent] is true the loading
  /// spinner is suppressed (used to reconcile mid-import without flicker).
  Future<void> loadAll({bool silent = false}) async {
    if (!silent) _loading = true;
    _error = null;
    _notify();
    try {
      _projects = await PaintProject.scanAll();
    } catch (e) {
      _error = '$e';
      LogService.log('[ProjectManager] loadAll failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Permanently deletes a project's file or folder, then reloads.
  Future<void> deleteProject(PaintProject project) async {
    try {
      final entity = project.type == PaintProjectType.dolphin
          ? io.Directory(project.path)
          : io.File(project.path);
      if (await entity.exists()) {
        await entity.delete(recursive: true);
      }
      if (_selectedId == project.id) {
        _selectedId = null;
        VirtualDisplaySession.instance.clearPreview();
      }
    } catch (e) {
      _error = 'Delete failed: $e';
      LogService.log('[ProjectManager] delete failed: $e');
    }
    await loadAll(silent: true);
  }

  /// Downloads the entire `/ext/dolphin` tree from the connected device into the
  /// local library, surfacing each animation as soon as its folder lands.
  Future<void> importFromDevice() async {
    if (_importing) return;
    if (!_client.isConnected) {
      _error = 'No device connected';
      _notify();
      return;
    }
    _importing = true;
    _importProgress = null;
    _importStatus = 'Listing /ext/dolphin…';
    _error = null;
    _notify();

    try {
      final localRoot = await appDolphinAnimationsDirectory();

      final files = <_RemoteFile>[];
      await _collectRemoteFiles(kDeviceDolphinPath, '', files);

      if (files.isEmpty) {
        _error = 'No animations found on device';
        return;
      }

      final totalBytes = files.fold<int>(0, (s, f) => s + f.size);
      var doneBytes = 0;
      final sep = io.Platform.pathSeparator;

      // Group by top-level folder so each animation appears as it completes.
      final order = <String>[];
      final groups = <String, List<_RemoteFile>>{};
      for (final f in files) {
        final slash = f.relPath.indexOf('/');
        final key = slash < 0 ? '' : f.relPath.substring(0, slash);
        if (!groups.containsKey(key)) {
          groups[key] = [];
          order.add(key);
        }
        groups[key]!.add(f);
      }

      var fileIndex = 0;
      for (final key in order) {
        for (final f in groups[key]!) {
          fileIndex++;
          _importStatus =
              'Downloading ${f.relPath} ($fileIndex/${files.length})';
          _notify();

          final bytes = await _client.storageReadChunked(
            f.remotePath,
            expectedSize: f.size,
            onProgress: (p) {
              if (totalBytes <= 0) return;
              _importProgress =
                  ((doneBytes + p * f.size) / totalBytes).clamp(0.0, 1.0);
              _notify();
            },
          );

          final localPath =
              '${localRoot.path}$sep${f.relPath.replaceAll('/', sep)}';
          final localFile = io.File(localPath);
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(bytes, flush: true);

          doneBytes += f.size;
          _importProgress =
              totalBytes > 0 ? (doneBytes / totalBytes).clamp(0.0, 1.0) : null;
          _notify();
        }

        // Folder fully downloaded → reflect it in the list immediately.
        if (key.isNotEmpty) await loadAll(silent: true);
      }
    } catch (e) {
      _error = 'Import failed: $e';
      LogService.log('[ProjectManager] import failed: $e');
    } finally {
      _importing = false;
      _importProgress = null;
      _importStatus = null;
      _notify();
    }

    await loadAll(silent: true);
  }

  Future<void> _collectRemoteFiles(
    String remotePath,
    String relPath,
    List<_RemoteFile> out,
  ) async {
    final batch = await _client.storageList(
      ListRequest(path: remotePath),
      timeout: const Duration(seconds: 30),
    );
    for (final r in batch.items) {
      for (final f in r.file) {
        final name = f.name;
        if (name.isEmpty) continue;
        final childRel = relPath.isEmpty ? name : '$relPath/$name';
        if (f.type == File_FileType.DIR) {
          await _collectRemoteFiles('$remotePath/$name', childRel, out);
        } else {
          out.add(
            _RemoteFile(
              remotePath: '$remotePath/$name',
              relPath: childRel,
              size: f.size,
            ),
          );
        }
      }
    }
  }


  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    VirtualDisplaySession.instance.leave();
    super.dispose();
  }
}

class _RemoteFile {
  _RemoteFile({
    required this.remotePath,
    required this.relPath,
    required this.size,
  });

  final String remotePath;
  final String relPath;
  final int size;
}
