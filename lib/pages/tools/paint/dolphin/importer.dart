import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';

import '../../../../services/logging.dart';
import '../../../../services/progress_throttle.dart';
import '../manager/controller.dart' show kDeviceDolphinPath;

enum ImportPhase { listing, checking, downloading }

/// Progress of a running [DolphinImporter.run].
///
/// [current]/[total] count animations while listing, files while checking and
/// downloading; [ratio] is 0..1 within the phase — byte-weighted once files are
/// actually moving — and null while the total is still unknown.
class ImportProgress {
  ImportProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.name,
    required this.ratio,
    this.fileProgress,
  });

  final ImportPhase phase;
  final int current;
  final int total;
  final String name;
  final double? ratio;
  final double? fileProgress;
}

class RemoteAnimationFile {
  RemoteAnimationFile({
    required this.remotePath,
    required this.relPath,
    required this.size,
    required this.md5,
  });

  final String remotePath;
  final String relPath;
  final int size;

  /// md5 as reported by the device's listing; empty when it did not give one.
  final String md5;
}

/// Mirrors `/ext/dolphin` into the local library.
///
/// The device is asked for one folder at a time — a single recursive listing
/// with md5 makes the Flipper hash every file before it answers, which blows
/// past any sane timeout and leaves the UI with nothing to show. Per folder it
/// stays responsive, every phase reports progress, and files whose md5 already
/// matches the local copy are never transferred.
abstract final class DolphinImporter {
  static const Duration _listTimeout = Duration(seconds: 60);

  /// Returns how many files were written. [onFolder] fires after each animation
  /// folder is complete, so the library can surface it right away.
  static Future<int> run({
    required FlipperClient client,
    required String localRoot,
    required void Function(ImportProgress) onProgress,
    required Future<void> Function() onFolder,
  }) async {
    final sep = io.Platform.pathSeparator;
    final folders = await _listFolders(client);
    if (folders.isEmpty) return 0;

    // Phase 1 — walk the folders one by one, hashing on the device as we go.
    final files = <RemoteAnimationFile>[];
    for (var i = 0; i < folders.length; i++) {
      final folder = folders[i];
      onProgress(
        ImportProgress(
          phase: ImportPhase.listing,
          current: i + 1,
          total: folders.length,
          name: folder.isEmpty ? kDeviceDolphinPath : folder,
          ratio: (i + 1) / folders.length,
        ),
      );
      files.addAll(await _listFiles(client, folder));
    }
    if (files.isEmpty) return 0;

    // Phase 2 — skip whatever is already mirrored byte-for-byte.
    final pending = <RemoteAnimationFile>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      onProgress(
        ImportProgress(
          phase: ImportPhase.checking,
          current: i + 1,
          total: files.length,
          name: f.relPath,
          ratio: (i + 1) / files.length,
        ),
      );
      final localPath = '$localRoot$sep${f.relPath.replaceAll('/', sep)}';
      if (await _localMatches(localPath, f.md5)) continue;
      pending.add(f);
    }
    if (pending.isEmpty) return 0;

    // Phase 3 — download what is left, grouped so a folder lands complete.
    final order = <String>[];
    final groups = <String, List<RemoteAnimationFile>>{};
    for (final f in pending) {
      final slash = f.relPath.indexOf('/');
      final key = slash < 0 ? '' : f.relPath.substring(0, slash);
      (groups[key] ??= (order..add(key), <RemoteAnimationFile>[]).$2).add(f);
    }

    final totalBytes = pending.fold<int>(0, (s, f) => s + f.size);
    final throttle = ProgressThrottle();
    var doneBytes = 0;
    var index = 0;

    for (final key in order) {
      for (final f in groups[key]!) {
        index++;
        void publish(double fileProgress) {
          onProgress(
            ImportProgress(
              phase: ImportPhase.downloading,
              current: index,
              total: pending.length,
              name: f.relPath,
              ratio: totalBytes <= 0
                  ? null
                  : ((doneBytes + fileProgress * f.size) / totalBytes).clamp(
                      0.0,
                      1.0,
                    ),
              fileProgress: fileProgress,
            ),
          );
        }

        throttle.reset();
        publish(0);

        final bytes = await client.storageReadChunked(
          f.remotePath,
          expectedSize: f.size,
          onProgress: (p) {
            if (throttle.shouldEmit(p)) publish(p);
          },
        );

        final localFile = io.File(
          '$localRoot$sep${f.relPath.replaceAll('/', sep)}',
        );
        await localFile.parent.create(recursive: true);
        await localFile.writeAsBytes(bytes, flush: true);

        doneBytes += f.size;
        publish(1);
      }
      if (key.isNotEmpty) await onFolder();
    }
    return pending.length;
  }

  /// Top-level animation folders; the empty string stands for files sitting
  /// directly in `/ext/dolphin` (the manifest).
  static Future<List<String>> _listFolders(FlipperClient client) async {
    final batch = await client.storageList(
      ListRequest(path: kDeviceDolphinPath),
      timeout: _listTimeout,
    );
    final folders = <String>[''];
    for (final r in batch.items) {
      for (final f in r.file) {
        if (f.name.isEmpty) continue;
        if (f.type == File_FileType.DIR) folders.add(f.name);
      }
    }
    return folders;
  }

  /// Files inside one folder, with the device's md5 for each. A failed listing
  /// yields nothing rather than aborting the whole import.
  static Future<List<RemoteAnimationFile>> _listFiles(
    FlipperClient client,
    String folder,
  ) async {
    final remoteDir = folder.isEmpty
        ? kDeviceDolphinPath
        : '$kDeviceDolphinPath/$folder';
    try {
      final batch = await client.storageList(
        ListRequest(path: remoteDir, includeMd5: true),
        timeout: _listTimeout,
      );
      final out = <RemoteAnimationFile>[];
      for (final r in batch.items) {
        for (final f in r.file) {
          if (f.name.isEmpty || f.type != File_FileType.FILE) continue;
          out.add(
            RemoteAnimationFile(
              remotePath: '$remoteDir/${f.name}',
              relPath: folder.isEmpty ? f.name : '$folder/${f.name}',
              size: f.size,
              md5: f.md5sum,
            ),
          );
        }
      }
      return out;
    } catch (e) {
      LogService.log('[DolphinImporter] list $remoteDir failed: $e');
      return const [];
    }
  }

  /// True when the local copy is byte-for-byte the file on the device.
  static Future<bool> _localMatches(String path, String remoteMd5) async {
    final want = remoteMd5.trim().toLowerCase();
    if (want.isEmpty) return false;
    try {
      final file = io.File(path);
      if (!await file.exists()) return false;
      return md5.convert(await file.readAsBytes()).toString().toLowerCase() ==
          want;
    } catch (_) {
      return false;
    }
  }
}
