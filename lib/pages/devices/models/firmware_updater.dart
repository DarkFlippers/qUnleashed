import 'dart:async';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flipperlib/flipperlib.dart';

import '../../../config.dart';
import 'firmware_directory.dart';
import 'ofw_parser.dart';
import 'unleashed_parser.dart';

const _tag = '[FirmwareUpdater]';
const _remoteRoot = '/ext/update';

void _log(String msg) {
  LogService.log('$_tag $msg');
}

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateFetching extends UpdateState {
  const UpdateFetching();
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.progress);
  final double progress;
}

class UpdateUploading extends UpdateState {
  const UpdateUploading(this.progress);
  final double progress;
}

class UpdateStarting extends UpdateState {
  const UpdateStarting();
}

class UpdateDone extends UpdateState {
  const UpdateDone();
}

class UpdateError extends UpdateState {
  const UpdateError(this.message);
  final String message;
}

class _UpdateFile {
  _UpdateFile(this.name, this.data);
  final String name;
  final List<int> data;
}

class FirmwareUpdater {
  FirmwareUpdater._();

  static FirmwareParser parserFor(FirmwareEntry entry) => switch (entry.shortName) {
        'ofw' => OfwParser.instance,
        'unlshd' => UnleashedParser.instance,
        _ => OfwParser.instance,
      };

  static Future<void> install({
    required FirmwareEntry entry,
    required String channelId,
    String target = 'f7',
    UnleashedVariant variant = UnleashedVariant.base,
    required FlipperClient client,
    required void Function(UpdateState) onState,
  }) async {
    final tempDir = io.Directory.systemTemp.createTempSync('flipper_fw_');
    try {
      onState(const UpdateFetching());
      final parser = parserFor(entry);
      await parser.get();

      final version = parser.getLatestVersionById(channelId);
      if (version == null) {
        onState(const UpdateError('No version found for selected channel'));
        return;
      }

      final FirmwareFile? tgzFile;
      if (parser is UnleashedParser) {
        tgzFile = parser.getUpdatePackage(channelId, target: target, variant: variant);
      } else if (parser is OfwParser) {
        tgzFile = parser.getUpdatePackage(channelId);
      } else {
        tgzFile = version.updatePackageFor(target);
      }
      if (tgzFile == null) {
        onState(UpdateError('No update_tgz for target=$target'));
        return;
      }

      onState(const UpdateDownloading(0));
      final tgzPath = '${tempDir.path}/update.tgz';
      await _downloadFile(tgzFile.url, tgzPath, (p) {
        onState(UpdateDownloading(p));
      });

      final extracted = _extractFlat(tgzPath);
      if (extracted.dirName == null || extracted.files.isEmpty) {
        onState(const UpdateError('Update archive is empty or malformed'));
        return;
      }

      final remoteDir = '$_remoteRoot/${extracted.dirName}';
      _log('remote dir: $remoteDir');

      await _mkdirSafe(client, _remoteRoot);
      await _mkdirSafe(client, remoteDir);

      final totalSize = extracted.files.fold<int>(0, (s, f) => s + f.data.length);
      var bytesUploaded = 0;
      String? manifestPath;

      for (final f in extracted.files) {
        final flipperPath = '$remoteDir/${f.name}';
        if (f.name == 'update.fuf') manifestPath = flipperPath;

        await _deleteSafe(client, flipperPath);

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
      await client.update(UpdateRequest(updateManifest: manifestPath));

      _log('rebooting to updater');
      try {
        await client.reboot(
          RebootRequest(mode: RebootRequest_RebootMode.UPDATE),
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {}

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

  static ({String? dirName, List<_UpdateFile> files}) _extractFlat(String tgzPath) {
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

  static Future<void> _deleteSafe(FlipperClient client, String path) async {
    try {
      await client.storageDelete(DeleteRequest(path: path));
    } catch (_) {}
  }

  static Future<void> _downloadFile(
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
        throw io.HttpException('Download failed: ${res.statusCode}', uri: Uri.parse(url));
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
