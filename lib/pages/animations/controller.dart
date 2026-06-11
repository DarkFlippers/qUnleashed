import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../services/repository/app.dart';
import 'dolphin_animation.dart';

/// Remote dolphin directory on the Flipper SD card.
const String kDeviceDolphinPath = '/ext/dolphin';

class AnimationManagerController extends ChangeNotifier {
  AnimationManagerController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _connSub = _client.connectionStream.listen((_) => _notify());
  }

  final FlipperClient _client;
  StreamSubscription<FlipperConnectionState>? _connSub;
  bool _disposed = false;

  List<DolphinAnimation> _animations = const [];
  bool _loading = false;
  bool _importing = false;
  double? _importProgress;
  String? _importStatus;
  String? _selectedName;
  String? _error;

  // ── Getters ────────────────────────────────────────────────────────────────

  List<DolphinAnimation> get animations => _animations;
  bool get loading => _loading;
  bool get importing => _importing;
  double? get importProgress => _importProgress;
  String? get importStatus => _importStatus;
  String? get error => _error;
  bool get isConnected => _client.isConnected;

  String? get selectedName => _selectedName;
  DolphinAnimation? get selected {
    final name = _selectedName;
    if (name == null) return null;
    for (final a in _animations) {
      if (a.name == name) return a;
    }
    return null;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void select(String? name) {
    _selectedName = (_selectedName == name) ? null : name;
    _notify();
  }

  /// Loads the local mirror (`Animations/dolphin`) into [animations]. When
  /// [silent] is true the loading spinner is suppressed and the list is updated
  /// in place — used to reconcile after an incremental import without hiding the
  /// previews that already appeared.
  Future<void> loadLocal({bool silent = false}) async {
    if (!silent) _loading = true;
    _error = null;
    _notify();
    try {
      final dir = await appDolphinAnimationsDirectory();
      _animations = await DolphinAnimationParser.scanDirectory(dir);
    } catch (e) {
      _error = '$e';
      LogService.log('[AnimationManager] loadLocal failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Downloads the entire `/ext/dolphin` tree from the connected device into the
  /// local mirror, then reloads. No-op (with [error] set) when disconnected.
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

      // First pass: enumerate every remote file so progress is meaningful.
      final files = <_RemoteFile>[];
      await _collectRemoteFiles(kDeviceDolphinPath, '', files);

      if (files.isEmpty) {
        _error = 'No animations found on device';
        return;
      }

      final totalBytes = files.fold<int>(0, (s, f) => s + f.size);
      var doneBytes = 0;
      final sep = io.Platform.pathSeparator;

      // Group files by their top-level folder (one animation each) so each
      // animation's preview can be published the moment its files land, rather
      // than waiting for the whole import to finish.
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

        // Folder fully downloaded → parse and surface it immediately.
        if (key.isNotEmpty) {
          await _publishLocalFolder(localRoot, key);
        }
      }
    } catch (e) {
      _error = 'Import failed: $e';
      LogService.log('[AnimationManager] import failed: $e');
    } finally {
      _importing = false;
      _importProgress = null;
      _importStatus = null;
      _notify();
    }

    await loadLocal(silent: true);
  }

  /// Parses one just-downloaded animation folder and merges it into
  /// [animations] (replacing any prior entry with the same name), so its
  /// preview shows up mid-import.
  Future<void> _publishLocalFolder(io.Directory localRoot, String name) async {
    try {
      final dir = io.Directory(pathJoin([localRoot.path, name]));
      final meta = io.File(pathJoin([dir.path, 'meta.txt']));
      if (!await meta.exists()) return;
      final anim = await DolphinAnimationParser.parseFolder(dir, meta);
      if (anim == null) return;
      final next = [
        ..._animations.where((a) => a.name != anim.name),
        anim,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _animations = next;
      _notify();
    } catch (e) {
      LogService.log('[AnimationManager] publish "$name" failed: $e');
    }
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

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
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
