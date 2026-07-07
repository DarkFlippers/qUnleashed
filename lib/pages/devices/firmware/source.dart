import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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
    await _verifySha256(tgzPath, tgzFile.sha256);
    return tgzPath;
  }

  // This archive gets flashed to the device; a truncated or tampered download
  // must never reach it. Variant builds publish no checksum (sha256 empty) and
  // are skipped.
  static Future<void> _verifySha256(String path, String expected) async {
    final want = expected.trim().toLowerCase();
    if (want.isEmpty) return;
    final got = await compute(_fileSha256, path);
    if (got != want) {
      throw FirmwareSourceException(
        'Firmware archive checksum mismatch (expected $want, got $got); '
        'the download is corrupted — try again',
      );
    }
  }

  static String _fileSha256(String path) =>
      sha256.convert(io.File(path).readAsBytesSync()).toString();

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
