import 'dart:async';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../../../storage/app_documents.dart';

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
    final base = await appDocumentsDirectory();
    final dir = io.Directory(pathJoin([base.path, 'IRDB']));
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
    final client = io.HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final req = await client.getUrl(url);
    req.headers.set(io.HttpHeaders.userAgentHeader, 'qunleashed-irlib');
    if (token.trim().isNotEmpty) {
      req.headers.set(
        io.HttpHeaders.authorizationHeader,
        'Bearer ${token.trim()}',
      );
    }
    final res = await req.close();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      client.close(force: true);
      throw Exception('Download failed (${res.statusCode}) for $url');
    }

    final total = res.contentLength;
    var received = 0;
    final tempDir = await getTemporaryDirectory();
    final sep = io.Platform.pathSeparator;
    final tempZip = io.File(
      '${tempDir.path}${sep}irdb-${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    final sink = tempZip.openWrite();
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          IrLibDownloadProgress(
            stage: 'Downloading',
            received: received,
            total: total,
          ),
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
      client.close(force: true);
    }

    onProgress?.call(
      IrLibDownloadProgress(
        stage: 'Unpacking',
        received: received,
        total: total,
      ),
    );

    try {
      final input = InputFileStream(tempZip.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        final totalFiles = archive.files.where((f) => f.isFile).length;
        var extracted = 0;

        onProgress?.call(
          IrLibDownloadProgress(
            stage: 'Unpacking',
            received: received,
            total: total,
            extracted: extracted,
            totalFiles: totalFiles,
          ),
        );

        for (final entry in archive.files) {
          var name = entry.name.replaceAll('\\', '/');
          final slash = name.indexOf('/');
          if (slash < 0) continue;
          name = name.substring(slash + 1);
          if (name.isEmpty) continue;
          final outPath = '${root.path}$sep${name.replaceAll('/', sep)}';
          if (entry.isFile) {
            final file = io.File(outPath);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(entry.readBytes()!, flush: true);
            extracted += 1;
            if (extracted % 25 == 0 || extracted == totalFiles) {
              onProgress?.call(
                IrLibDownloadProgress(
                  stage: 'Unpacking',
                  received: received,
                  total: total,
                  extracted: extracted,
                  totalFiles: totalFiles,
                ),
              );
            }
          } else {
            await io.Directory(outPath).create(recursive: true);
          }
        }

        onProgress?.call(
          IrLibDownloadProgress(
            stage: 'Done',
            received: received,
            total: total,
            extracted: extracted,
            totalFiles: totalFiles,
          ),
        );
      } finally {
        await input.close();
      }
    } finally {
      if (await tempZip.exists()) {
        try {
          await tempZip.delete();
        } catch (_) {}
      }
    }

    return root;
  }
}
