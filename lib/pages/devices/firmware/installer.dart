import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flipperlib/dfu/stm32wb55/option_bytes.dart';
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

      if (!client.isConnected) {
        await _installViaDfu(extracted.files, onState);
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

  static Future<void> _installViaDfu(
    List<_UpdateFile> files,
    void Function(UpdateState) onState,
  ) async {
    final byName = {for (final f in files) f.name: f};
    _log('DFU recovery; bundle files: ${byName.keys.join(', ')}');

    final fuf = _parseFuf(byName['update.fuf']?.data);
    final firmwareName = fuf?.firmware ?? 'firmware.dfu';
    final firmware = byName[firmwareName];
    if (firmware == null) {
      onState(UpdateError('No $firmwareName in update bundle'));
      return;
    }
    if (fuf == null) {
      onState(const UpdateError('No valid update.fuf in update bundle'));
      return;
    }
    final obError = fuf.optionBytesError;
    if (obError != null) {
      onState(UpdateError(obError));
      return;
    }
    final radio = fuf.radio == null ? null : byName[fuf.radio!];
    _log(
      'DFU files: firmware=$firmwareName(${firmware.data.length}B) '
      'radio=${fuf.radio}(${radio?.data.length ?? 0}B) '
      'manifest radioAddr=0x${(fuf.radioAddress ?? 0).toRadixString(16)} '
      '(unused: target is derived from SFSA, as in qFlipper) '
      'obRef=${fuf.obReference?.length} '
      'obCompare=${fuf.obCompareMask?.length} '
      'obWrite=${fuf.obWriteMask?.length}',
    );

    final request = RecoveryRequest(
      firmwareDfu: Uint8List.fromList(firmware.data),
      radioBin: radio == null ? null : Uint8List.fromList(radio.data),
      obReference: fuf.obReference!,
      obCompareMask: fuf.obCompareMask!,
      obWriteMask: fuf.obWriteMask!,
    );

    onState(const UpdateUploading(0));
    final done = Completer<void>();
    Object? failure;
    final sub = runRecovery(request).listen(
      (message) {
        switch (message) {
          case RecoveryProgress(:final step, :final percent):
            onState(_dfuProgressState(step, percent));
          case RecoveryLog(:final message):
            _log('DFU: $message');
          case RecoveryDone():
            if (!done.isCompleted) done.complete();
          case RecoveryFailed(:final error):
            failure = error;
            if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object e) {
        failure = e;
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    await sub.cancel();

    if (failure != null) {
      onState(UpdateError(failure.toString()));
    } else {
      onState(const UpdateWaitingForReconnect());
    }
  }

  static UpdateState _dfuProgressState(RecoveryStep step, double percent) {
    return UpdateRecovering(step, (percent / 100).clamp(0.0, 1.0));
  }

  static _Fuf? _parseFuf(List<int>? data) {
    if (data == null) return null;
    final text = String.fromCharCodes(data);
    String? firmware;
    String? radio;
    int? radioAddress;
    Uint8List? obReference;
    Uint8List? obCompareMask;
    Uint8List? obWriteMask;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final i = line.indexOf(':');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final value = line.substring(i + 1).trim();
      switch (key) {
        case 'Firmware':
          firmware = value;
        case 'Radio':
          radio = value;
        case 'Radio address':
          radioAddress = _parseLeAddress(value);
        case 'OB reference':
          obReference = _parseHexBytes(value);
        case 'OB mask':
          obCompareMask = _parseHexBytes(value);
        case 'OB write mask':
          obWriteMask = _parseHexBytes(value);
      }
    }
    return _Fuf(
      firmware: firmware,
      radio: radio,
      radioAddress: radioAddress,
      obReference: obReference,
      obCompareMask: obCompareMask,
      obWriteMask: obWriteMask,
    );
  }

  static int? _parseLeAddress(String value) {
    final bytes = _parseHexBytes(value);
    if (bytes == null || bytes.isEmpty) return null;
    var result = 0;
    for (var i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | bytes[i];
    }
    return result;
  }

  static Uint8List? _parseHexBytes(String value) {
    final tokens = value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final bytes = <int>[];
    for (final t in tokens) {
      final b = int.tryParse(t, radix: 16);
      if (b == null) return null;
      bytes.add(b & 0xFF);
    }
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
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

class _Fuf {
  _Fuf({
    this.firmware,
    this.radio,
    this.radioAddress,
    this.obReference,
    this.obCompareMask,
    this.obWriteMask,
  });

  final String? firmware;
  final String? radio;
  final int? radioAddress;
  final Uint8List? obReference;
  final Uint8List? obCompareMask;
  final Uint8List? obWriteMask;

  String? get optionBytesError {
    const size = OptionBytes.sizeBytes;
    if (obReference?.length != size) {
      return 'Invalid or missing OB reference in update.fuf';
    }
    if (obCompareMask?.length != size) {
      return 'Invalid or missing OB mask in update.fuf';
    }
    if (obWriteMask?.length != size) {
      return 'Invalid or missing OB write mask in update.fuf';
    }
    return null;
  }
}
