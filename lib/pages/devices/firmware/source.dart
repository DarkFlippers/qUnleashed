import 'dart:io' as io;

import '../../../config.dart';
import 'directory.dart';

abstract class FirmwareSource {
  Future<String> resolveArchive(
    String tmpDir,
    void Function(double progress) onProgress,
  );

  bool get isRemote;
}

class RemoteFirmwareSource implements FirmwareSource {
  RemoteFirmwareSource({
    required this.entry,
    required this.channelId,
    this.target = 'f7',
    this.variant = UnleashedVariant.base,
  });

  final FirmwareEntry entry;
  final String channelId;
  final String target;
  final UnleashedVariant variant;

  @override
  bool get isRemote => true;

  @override
  Future<String> resolveArchive(
    String tmpDir,
    void Function(double progress) onProgress,
  ) async {
    final parser = parserForEntry(entry);
    await parser.get();

    final version = parser.getLatestVersionById(channelId);
    if (version == null) {
      throw const FirmwareSourceException(
        'No version found for selected channel',
      );
    }

    final FirmwareFile? tgzFile = parser is UnleashedParser
        ? parser.getUpdatePackage(channelId, target: target, variant: variant)
        : version.updatePackageFor(target);
    if (tgzFile == null) {
      throw FirmwareSourceException('No update_tgz for target=$target');
    }

    final tgzPath = '$tmpDir/update.tgz';
    await _download(tgzFile.url, tgzPath, onProgress);
    return tgzPath;
  }

  static Future<void> _download(
    String url,
    String savePath,
    void Function(double progress) onProgress,
  ) async {
    final client = io.HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(io.HttpHeaders.userAgentHeader, 'qunleashed-app');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw io.HttpException(
          'Download failed: ${res.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final contentLength = res.contentLength;
      final sink = io.File(savePath).openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) onProgress(received / contentLength);
      }
      await sink.flush();
      await sink.close();
      if (contentLength <= 0) onProgress(1.0);
    } finally {
      client.close();
    }
  }
}

class LocalFirmwareSource implements FirmwareSource {
  LocalFirmwareSource(this.path);

  final String path;

  @override
  bool get isRemote => false;

  @override
  Future<String> resolveArchive(
    String tmpDir,
    void Function(double progress) onProgress,
  ) async {
    if (!io.File(path).existsSync()) {
      throw FirmwareSourceException('File not found: $path');
    }
    return path;
  }
}

class FirmwareSourceException implements Exception {
  const FirmwareSourceException(this.message);
  final String message;

  @override
  String toString() => message;
}
