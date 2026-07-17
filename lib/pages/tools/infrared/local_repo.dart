import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../../../services/http/app_http.dart';
import '../../../services/repository/app.dart';

class IrLibDownloadProgress {
  IrLibDownloadProgress({
    required this.stage,
    this.received = 0,
    this.total = 0,
    this.extracted = 0,
    this.totalFiles = 0,
  });

  final String stage;
  final int received;
  final int total;
  final int extracted;
  final int totalFiles;

  bool get isExtracting => totalFiles > 0;

  double get fraction {
    if (totalFiles > 0) {
      return (extracted / totalFiles).clamp(0.0, 1.0);
    }
    if (total > 0) {
      return (received / total).clamp(0.0, 1.0);
    }
    if (received > 0) {
      final mb = received / (1024 * 1024);
      return (mb / (mb + 8)).clamp(0.02, 0.92);
    }
    return 0.0;
  }
}

class IrLibLocalRepo {
  IrLibLocalRepo();

  static io.Directory? _cachedRoot;

  Future<io.Directory> resolveRoot() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;
    final dir = await irLibRepositoryDirectory();
    _cachedRoot = dir;
    return dir;
  }

  Future<bool> exists() async {
    final dir = await resolveRoot();
    if (!await dir.exists()) return false;
    await for (final _ in dir.list(followLinks: false)) {
      return true;
    }
    return false;
  }

  Future<DateTime?> lastModified() async {
    final dir = await resolveRoot();
    if (!await dir.exists()) return null;
    try {
      final stat = await dir.stat();
      return stat.modified;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteAll() async {
    final dir = await resolveRoot();
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } on io.PathNotFoundException {
      return;
    }
  }

  Future<io.Directory> download({
    required String owner,
    required String repo,
    required String branch,
    String token = '',
    void Function(IrLibDownloadProgress)? onProgress,
  }) async {
    final root = await resolveRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);

    onProgress?.call(IrLibDownloadProgress(stage: 'Downloading'));

    final url = Uri.parse(
      'https://codeload.github.com/$owner/$repo/zip/refs/heads/$branch',
    );
    final tempDir = await getTemporaryDirectory();
    final sep = io.Platform.pathSeparator;
    final tempZip = io.File(
      '${tempDir.path}${sep}irdb-${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    var received = 0;
    var total = 0;
    await AppHttp.downloadToFile(
      url,
      tempZip.path,
      headers: {
        io.HttpHeaders.userAgentHeader: 'qunleashed-irlib',
        if (token.trim().isNotEmpty)
          io.HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
      },
      onProgress: (bytes, totalBytes) {
        received = bytes;
        total = totalBytes ?? 0;
        onProgress?.call(
          IrLibDownloadProgress(
            stage: 'Downloading',
            received: received,
            total: total,
          ),
        );
      },
    );

    onProgress?.call(
      IrLibDownloadProgress(
        stage: 'Unpacking',
        received: received,
        total: total,
      ),
    );

    try {
      await _unpackInIsolate(
        zipPath: tempZip.path,
        rootPath: root.path,
        sep: sep,
        onProgress: (extracted, totalFiles, done) {
          onProgress?.call(
            IrLibDownloadProgress(
              stage: done ? 'Done' : 'Unpacking',
              received: received,
              total: total,
              extracted: extracted,
              totalFiles: totalFiles,
            ),
          );
        },
      );
    } finally {
      if (await tempZip.exists()) {
        try {
          await tempZip.delete();
        } catch (_) {}
      }
    }

    return root;
  }

  /// Inflates the IR database zip and writes every entry to disk inside a
  /// background isolate. Unpacking thousands of files must never block the UI
  /// isolate; progress is streamed back over a [SendPort].
  static Future<void> _unpackInIsolate({
    required String zipPath,
    required String rootPath,
    required String sep,
    required void Function(int extracted, int totalFiles, bool done)
        onProgress,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final done = Completer<void>();

    receivePort.listen((msg) {
      if (msg is _UnpackProgress) {
        onProgress(msg.extracted, msg.totalFiles, msg.done);
        if (msg.done && !done.isCompleted) done.complete();
      }
    });
    errorPort.listen((msg) {
      if (done.isCompleted) return;
      final error = (msg is List && msg.isNotEmpty) ? msg.first : msg;
      done.completeError(StateError('IR unpack failed: $error'));
    });

    final isolate = await Isolate.spawn(
      _unpackIsolateEntry,
      _UnpackArgs(zipPath, rootPath, sep, receivePort.sendPort),
      onError: errorPort.sendPort,
      errorsAreFatal: true,
      debugName: 'irlib-unpack',
    );

    try {
      await done.future;
    } finally {
      isolate.kill(priority: Isolate.beforeNextEvent);
      receivePort.close();
      errorPort.close();
    }
  }

  static void _unpackIsolateEntry(_UnpackArgs args) {
    final send = args.sendPort;
    final input = InputFileStream(args.zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final totalFiles = archive.files.where((f) => f.isFile).length;
      var extracted = 0;
      send.send(_UnpackProgress(extracted, totalFiles, false));

      for (final entry in archive.files) {
        var name = entry.name.replaceAll('\\', '/');
        final slash = name.indexOf('/');
        if (slash < 0) continue;
        name = name.substring(slash + 1);
        if (name.isEmpty) continue;
        final outPath =
            '${args.rootPath}${args.sep}${name.replaceAll('/', args.sep)}';
        if (entry.isFile) {
          final file = io.File(outPath);
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(entry.readBytes()!, flush: true);
          extracted += 1;
          if (extracted % 25 == 0 || extracted == totalFiles) {
            send.send(_UnpackProgress(extracted, totalFiles, false));
          }
        } else {
          io.Directory(outPath).createSync(recursive: true);
        }
      }

      send.send(_UnpackProgress(extracted, totalFiles, true));
    } finally {
      input.close();
    }
  }
}

class _UnpackArgs {
  _UnpackArgs(this.zipPath, this.rootPath, this.sep, this.sendPort);
  final String zipPath;
  final String rootPath;
  final String sep;
  final SendPort sendPort;
}

class _UnpackProgress {
  _UnpackProgress(this.extracted, this.totalFiles, this.done);
  final int extracted;
  final int totalFiles;
  final bool done;
}
