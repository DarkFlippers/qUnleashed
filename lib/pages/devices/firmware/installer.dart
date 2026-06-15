import 'dart:async';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'source.dart';
import 'update_state.dart';

const _tag = '[FirmwareInstaller]';
const _remoteRoot = '/ext/update';

void _log(String msg) => LogService.log('$_tag $msg');

class FirmwareInstaller {
  const FirmwareInstaller._();

  static Future<void> install({
    required FirmwareSource source,
    required FlipperClient client,
    required void Function(UpdateState) onState,
  }) async {
    final tempDir = io.Directory.systemTemp.createTempSync('flipper_fw_');
    try {
      if (source.isRemote) onState(const UpdateFetching());

      final archivePath = await source.resolveArchive(
        tempDir.path,
        (p) => onState(UpdateDownloading(p)),
      );

      final extracted = await _extractFlat(archivePath);
      if (extracted.dirName == null || extracted.files.isEmpty) {
        onState(const UpdateError('Update archive is empty or malformed'));
        return;
      }

      final remoteDir = '$_remoteRoot/${extracted.dirName}';
      _log('archive root: ${extracted.dirName}; remote dir: $remoteDir');

      await _mkdirSafe(client, _remoteRoot);
      await _mkdirSafe(client, remoteDir);

      final totalSize = extracted.files.fold<int>(
        0,
        (s, f) => s + f.data.length,
      );
      var bytesUploaded = 0;
      String? manifestPath;

      for (final f in extracted.files) {
        final flipperPath = '$remoteDir/${f.name}';
        if (f.name == 'update.fuf') manifestPath = flipperPath;

        _log('uploading ${f.name} (${f.data.length}B)');
        final fileBytes = f.data.length;
        final entryStart = bytesUploaded;
        await client.storageWriteChunked(
          flipperPath,
          f.data,
          onProgress: (p) {
            final overall = totalSize == 0
                ? 1.0
                : (entryStart + fileBytes * p) / totalSize;
            onState(UpdateUploading(overall));
          },
        );
        bytesUploaded += fileBytes;
      }

      if (manifestPath == null) {
        onState(const UpdateError('No update.fuf manifest in archive'));
        return;
      }

      _log('starting update: $manifestPath');
      onState(const UpdateStarting());
      await client.runUpdate(UpdateRequest(updateManifest: manifestPath));

      onState(const UpdateDone());
    } catch (e, st) {
      _log('ERROR: $e\n$st');
      onState(UpdateError(e.toString()));
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static Future<({String? dirName, List<_UpdateFile> files})> _extractFlat(
    String tgzPath,
  ) => compute(_extractFlatIsolate, tgzPath);

  static ({String? dirName, List<_UpdateFile> files}) _extractFlatIsolate(
    String tgzPath,
  ) {
    final bytes = io.File(tgzPath).readAsBytesSync();
    final gz = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(gz);

    String? dirName;
    final files = <_UpdateFile>[];

    for (final f in archive.files) {
      if (!f.isFile) continue;
      final parts = f.name.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) continue;
      dirName ??= parts.first;
      if (parts.first != dirName) continue;
      final basename = parts.last;
      files.add(_UpdateFile(basename, f.content as List<int>));
    }

    return (dirName: dirName, files: files);
  }

  static Future<void> _mkdirSafe(FlipperClient client, String path) async {
    try {
      await client.storageMkdir(MkdirRequest(path: path));
    } catch (_) {}
  }
}

class _UpdateFile {
  _UpdateFile(this.name, this.data);
  final String name;
  final List<int> data;
}
