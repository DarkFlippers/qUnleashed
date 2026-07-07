import 'dart:io' as io;

import '../../../config.dart';
import '../../../services/http/app_http.dart';
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
    await AppHttp.downloadToFile(
      Uri.parse(url),
      savePath,
      onProgress: (received, total) {
        if (total != null && total > 0) onProgress(received / total);
      },
    );
    onProgress(1.0);
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
