import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';

import '../../../../services/logging.dart';
import '../../../../services/progress_throttle.dart';
import '../manager/controller.dart' show kDeviceDolphinPath;
import '../project.dart';
import 'dolphin_pack.dart';
import 'manifest.dart';

enum SendPhase { checking, sending }

/// Progress of a running [DolphinSender.send].
///
/// While checking, [current]/[total] count animations; while sending they count
/// files and [ratio] is byte-weighted over everything left to write, advanced
/// chunk by chunk from the local buffer as it is handed to the transport.
class SendProgress {
  SendProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.fileName,
    required this.ratio,
    this.fileProgress,
  });
  final SendPhase phase;
  final int current;
  final int total;
  final String fileName;
  final double ratio;
  final double? fileProgress;
}

class _PendingFile {
  _PendingFile({required this.dir, required this.name, required this.bytes});
  final String dir;
  final String name;
  final List<int> bytes;
}

/// Uploads a dolphin pack: the selected animations (`meta.txt` + `frame_*.bm`)
/// under `/ext/dolphin`, then the combined manifest last.
///
/// Every file is md5-checked against its counterpart on the device first, so
/// only the ones that really differ are written.
abstract final class DolphinSender {
  static Future<void> send({
    required FlipperClient client,
    required List<(PaintProject, ManifestEntry)> selected,
    required void Function(SendProgress) onProgress,
  }) async {
    await _writePending(
      client,
      await _planUpload(client, selected, onProgress),
      onProgress,
    );
  }

  /// Compares every file of every selected animation — and the manifest — with
  /// its md5 on the device, returning only the ones that really differ.
  static Future<List<_PendingFile>> _planUpload(
    FlipperClient client,
    List<(PaintProject, ManifestEntry)> selected,
    void Function(SendProgress) onProgress,
  ) async {
    final pending = <_PendingFile>[];
    final total = selected.length + 1; // animations + the manifest
    for (var i = 0; i < selected.length; i++) {
      final (project, entry) = selected[i];
      onProgress(_checking(i, total, entry.name));

      final files = await DolphinPack.buildFiles(project);
      if (files.isEmpty) continue;

      final dir = '$kDeviceDolphinPath/${entry.name}';
      final remote = await _remoteMd5s(client, dir);
      for (final f in files) {
        if (remote[f.name] != _md5(f.bytes)) {
          pending.add(_PendingFile(dir: dir, name: f.name, bytes: f.bytes));
        }
      }
    }

    const manifestName = 'manifest.txt';
    onProgress(_checking(selected.length, total, manifestName));
    final manifestBytes = DolphinManifest.build(
      selected.map((s) => s.$2),
    ).codeUnits;
    if (await _remoteMd5(client, '$kDeviceDolphinPath/$manifestName') !=
        _md5(manifestBytes)) {
      pending.add(
        _PendingFile(
          dir: kDeviceDolphinPath,
          name: manifestName,
          bytes: manifestBytes,
        ),
      );
    }
    return pending;
  }

  /// Writes [pending] in order, advancing progress per chunk handed to the
  /// transport: the ratio comes from the local buffers alone, so it never waits
  /// on the device to report anything back.
  static Future<void> _writePending(
    FlipperClient client,
    List<_PendingFile> pending,
    void Function(SendProgress) onProgress,
  ) async {
    final totalBytes = pending.fold<int>(0, (s, f) => s + f.bytes.length);
    final throttle = ProgressThrottle();
    final created = <String>{};
    var doneBytes = 0;

    for (var i = 0; i < pending.length; i++) {
      final f = pending[i];
      if (f.dir != kDeviceDolphinPath && created.add(f.dir)) {
        await _mkdirIgnoreExisting(client, f.dir);
      }
      throttle.reset();
      onProgress(
        _sending(i, pending.length, f, doneBytes, totalBytes, 0),
      );

      await client.storageWriteChunked(
        '${f.dir}/${f.name}',
        f.bytes,
        onProgress: (p) {
          if (!throttle.shouldEmit(p)) return;
          onProgress(_sending(i, pending.length, f, doneBytes, totalBytes, p));
        },
      );

      onProgress(_sending(i, pending.length, f, doneBytes, totalBytes, 1));
      doneBytes += f.bytes.length;
    }
  }

  static SendProgress _checking(int current, int total, String fileName) {
    return SendProgress(
      phase: SendPhase.checking,
      current: current,
      total: total,
      fileName: fileName,
      ratio: total == 0 ? 0 : (current / total).clamp(0.0, 1.0),
    );
  }

  static SendProgress _sending(
    int index,
    int total,
    _PendingFile file,
    int doneBytes,
    int totalBytes,
    double fileProgress,
  ) {
    return SendProgress(
      phase: SendPhase.sending,
      current: index + 1,
      total: total,
      fileName: file.name,
      ratio: totalBytes <= 0
          ? 1
          : ((doneBytes + fileProgress * file.bytes.length) / totalBytes).clamp(
              0.0,
              1.0,
            ),
      fileProgress: fileProgress,
    );
  }

  static String _md5(List<int> bytes) =>
      md5.convert(bytes).toString().toLowerCase();

  /// Remote md5 of every file directly inside [dir], keyed by file name. Empty
  /// when the folder does not exist yet or the listing fails.
  static Future<Map<String, String>> _remoteMd5s(
    FlipperClient client,
    String dir,
  ) async {
    try {
      final batch = await client.storageList(
        ListRequest(path: dir, includeMd5: true),
        timeout: const Duration(seconds: 30),
      );
      return {
        for (final r in batch.items)
          for (final f in r.file)
            if (f.type == File_FileType.FILE && f.name.isNotEmpty)
              f.name: f.md5sum.trim().toLowerCase(),
      };
    } catch (e) {
      LogService.log('[DolphinSender] md5 list $dir failed: $e');
      return const {};
    }
  }

  static Future<String> _remoteMd5(FlipperClient client, String path) async {
    try {
      final batch = await client.storageMd5sum(
        Md5sumRequest(path: path),
        timeout: const Duration(seconds: 15),
      );
      return (batch.items.isNotEmpty ? batch.items.first.md5sum : '')
          .trim()
          .toLowerCase();
    } catch (e) {
      LogService.log('[DolphinSender] md5 $path failed: $e');
      return '';
    }
  }

  static Future<void> _mkdirIgnoreExisting(
    FlipperClient client,
    String path,
  ) async {
    try {
      await client.storageMkdir(MkdirRequest(path: path));
    } catch (_) {
      // Folder already exists (or another benign error): files are written with
      // CREATE_ALWAYS, so an overwrite proceeds regardless.
    }
  }
}
