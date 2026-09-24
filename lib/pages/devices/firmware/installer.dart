import '../../../services/localization/l10n.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/connection/link_service.dart';
import '../../../services/progress_throttle.dart';
import 'source.dart';
import 'update_state.dart';
import '../../../services/logging.dart';

const _tag = '[FirmwareInstaller]';
const _remoteRoot = '/ext/update';

/// The installer's running commentary, tagged.
///
/// Commentary only. [LogService.info] is not kept and folds out of a release
/// build, so a failure that has to survive one says so at its own call site
/// rather than coming through here - which is why this helper does not carry
/// the level for every site in the file.
void _log(String msg) => LogService.info('$_tag $msg');

class FirmwareInstaller {
  const FirmwareInstaller._();

  /// Flashes [source] onto the Flipper that is in play when this is called.
  ///
  /// Declared as one task, so the directory it makes, every file it uploads,
  /// the md5 checks between them and the command that finally starts the update
  /// all reach that same Flipper. Warm sessions let the user switch devices
  /// without the link dropping, and before this the second half of a firmware
  /// went wherever they switched to - onto a Flipper holding the first half of
  /// nothing, told to install it.
  ///
  /// Nothing here gives up when the user switches. Half a firmware is worse
  /// than an old one, so a flash that has begun finishes where it began; what a
  /// switch changes is only which screen is entitled to show its progress, and
  /// that is [UpdateState.deviceId]'s job.
  static Future<void> install({
    required FirmwareSource source,
    required FlipperClient client,
    required void Function(UpdateState) onState,
  }) => client.runTask(
    FlipperRequestPriority.background,
    () => _install(source: source, client: client, onState: onState),
  );

  static Future<void> _install({
    required FirmwareSource source,
    required FlipperClient client,
    required void Function(UpdateState) onState,
  }) async {
    final tempDir = io.Directory.systemTemp.createTempSync('flipper_fw_');
    // The wait for the Flipper to come back happens after this directory is
    // gone: an install runs for as long as it runs - half an hour on a large
    // firmware - and an unpacked bundle has no business sitting on disk for
    // it.
    FlipperDevice? awaitReturnOf;
    try {
      if (source.isRemote) onState(const UpdateFetching());

      final downloadThrottle = ProgressThrottle();
      final archivePath = await source.resolveArchive(tempDir.path, (p) {
        if (downloadThrottle.shouldEmit(p)) onState(UpdateDownloading(p));
      });

      final extracted = await _extractFlat(archivePath);
      if (extracted.dirName == null || extracted.files.isEmpty) {
        onState(UpdateError(l10n.firmwareErrorEmptyArchive));
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

      final files = extracted.files;
      String? manifestPath;
      final uploadThrottle = ProgressThrottle();

      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final flipperPath = '$remoteDir/${f.name}';
        if (f.name == 'update.fuf') manifestPath = flipperPath;

        onState(UpdateVerifying(fileIndex: i + 1, fileCount: files.length));
        if (await _remoteMatches(client, flipperPath, f.md5)) {
          _log('keeping ${f.name}: md5 matches (${f.md5})');
          continue;
        }

        _log('uploading ${f.name} (${f.data.length}B)');
        uploadThrottle.reset();
        onState(UpdateUploading(0, fileIndex: i + 1, fileCount: files.length));
        await client.storageWriteChunked(
          flipperPath,
          f.data,
          onProgress: (p) {
            if (uploadThrottle.shouldEmit(p)) {
              onState(
                UpdateUploading(p, fileIndex: i + 1, fileCount: files.length),
              );
            }
          },
        );
      }

      if (manifestPath == null) {
        onState(UpdateError(l10n.firmwareErrorNoManifest));
        return;
      }

      _log('starting update: $manifestPath');
      onState(const UpdateStarting());
      final target = client.bindCurrentSession().device;
      await client.runUpdate(UpdateRequest(updateManifest: manifestPath));

      // Over USB the Flipper is followed through the install: it switches its
      // USB controller off to reboot into the updater, and the port coming
      // back is the signal to take the link again. Over BLE it is the user's
      // call — the radio comes back whenever the install is done, and only
      // they know when to reach for it.
      awaitReturnOf = (target?.isUsb ?? false) ? target : null;
      onState(
        awaitReturnOf != null ? const UpdateInstalling() : const UpdateDone(),
      );
    } catch (e, st) {
      // error rather than the commentary helper: UpdateError hands the UI
      // e.toString() and no stack, so this is the only place the stack for
      // a flash that died mid-write exists at all - and that is the one
      // failure in this app most worth reproducing from a bug report.
      LogService.error('$_tag update failed: $e\n$st');
      onState(UpdateError(e.toString()));
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }

    final target = awaitReturnOf;
    if (target == null) return;
    await LinkService.instance.awaitUsbReturn(target);
    _log('${target.name} is back on the cable');
    onState(const UpdateDone());
  }

  /// Waits for [client] to come back after a recovery flash.
  ///
  /// True if it did, false if it did not - a bad cable, a device that needs a
  /// manual power cycle, or a flash that left it unable to boot. The deadline
  /// is a return value rather than an exception because it is an outcome of
  /// the recovery, not a fault in the wait: whoever called has a transitional
  /// state to leave either way.
  ///
  /// It lives here rather than in the button because the state being waited
  /// out is the one this class enters - see the `UpdateWaitingForReconnect`
  /// below, which is the only place it is ever emitted. The button was just
  /// where the waiting happened to be written. #118.
  ///
  /// Not [FlipperClient.waitForRpcSession], which has the same shape and is
  /// not the same question. That one ends early on a terminal disconnect and
  /// requires a live transport, both right for a session that faulted and
  /// should come back - and both wrong here, where the device has just been
  /// flashed, is deliberately gone, and has to re-enumerate before any
  /// transport exists. It would report a brick the moment the old link died.
  static Future<bool> awaitReconnect(
    FlipperClient client, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (client.isConnected) return true;
    // The subscription is owned rather than left to `firstWhere`, because
    // `Future.timeout` times out the future and cannot reach the work behind
    // it: every recovery that ran out of time used to leave a listener on a
    // broadcast stream that lives as long as the client. Owning it also means
    // a stream that ends or errors is an outcome this can name, instead of
    // `firstWhere` raising a bare `StateError` for a closed stream.
    final done = Completer<bool>();
    void finish(bool back) {
      if (!done.isCompleted) done.complete(back);
    }

    final sub = client.connectionStream.listen(
      (_) {
        if (client.isConnected) finish(true);
      },
      // An error does not end a broadcast stream, so the reconnect can still
      // arrive: this is recorded and the wait runs on to the deadline. Ending
      // it here would turn one spurious error into a reported brick.
      onError: (Object e, StackTrace st) => LogService.warn(
        '$_tag reconnect wait saw a stream error: '
        '${LogService.describe(e, st)}',
      ),
      // The link ending says nothing about the device, and it ends
      // milliseconds after the flash rather than half a minute later - so
      // reporting a brick would be a guess written into the log as a fact, on
      // the most consequential screen in the app. Asking the client is the
      // only honest answer left, and it is only worth a line when the answer
      // is no: a device that came back quietly is a success, not a warning.
      onDone: () {
        if (!done.isCompleted && !client.isConnected) {
          LogService.warn('$_tag reconnect wait ended without an answer');
        }
        finish(client.isConnected);
      },
    );
    try {
      return await done.future.timeout(timeout);
    } on TimeoutException catch (e, st) {
      // error, not the commentary helper: the device was flashed and did not
      // come back, which is the worst outcome this app produces. Before #118
      // this exception was caught and dropped, so the one session most worth
      // reading a bug report about held nothing at all.
      LogService.error(
        '$_tag device did not reconnect after recovery: '
        '${LogService.describe(e, st)}',
      );
      return false;
    } finally {
      // Cancelled but not awaited. Releasing the listener is the whole reason
      // this owns the subscription; when that teardown finishes is nobody's
      // business, and the answer is already in hand. Awaiting it also wedged
      // the wait under the widget-test clock, where the cancel future did not
      // resolve inside a pump.
      unawaited(sub.cancel());
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
      onState(UpdateError(l10n.firmwareErrorNoBinary(firmwareName)));
      return;
    }
    if (fuf == null) {
      onState(UpdateError(l10n.firmwareErrorBadManifest));
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
          case RecoveryFailed(:final error, failure: final reason):
            // Recorded here because it cannot be recorded where it happened:
            // recovery runs in a spawned isolate, and flipperlib's log sink is
            // a static, so none of its own error logging reaches this one.
            // What crosses the port is the outcome, and without this a failed
            // flash leaves nothing behind in a build that prints nothing.
            LogService.error('[DFU] recovery failed ($reason): $error');
            failure = _dfuFailureMessage(reason, error);
            if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object e, StackTrace st) {
        LogService.error('[DFU] recovery stream failed: $e\n$st');
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

  static String _dfuFailureMessage(DfuHostFailure failure, String error) {
    return switch (failure) {
      DfuHostFailure.driverMissing => l10n.firmwareErrorDfuDriverMissing,
      DfuHostFailure.accessDenied => l10n.firmwareErrorDfuAccessDenied,
      DfuHostFailure.permissionDenied => l10n.firmwareErrorDfuPermissionDenied,
      DfuHostFailure.other => error,
    };
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
      // The archive root is later joined onto `/ext/update` as a directory on
      // the device, so a relative segment here would walk out of it.
      if (parts.first == '.' || parts.first == '..') continue;
      dirName ??= parts.first;
      if (parts.first != dirName) continue;
      final basename = parts.last;
      final content = f.content as List<int>;
      files.add(
        _UpdateFile(
          basename,
          content,
          md5.convert(content).toString().toLowerCase(),
        ),
      );
    }

    return (dirName: dirName, files: files);
  }

  static Future<bool> _remoteMatches(
    FlipperClient client,
    String path,
    String localMd5,
  ) async {
    try {
      final batch = await client.storageMd5sum(
        Md5sumRequest(path: path),
        timeout: const Duration(seconds: 60),
      );
      final remote = (batch.items.isNotEmpty ? batch.items.first.md5sum : '')
          .trim()
          .toLowerCase();
      return remote.isNotEmpty && remote == localMd5;
    } catch (e) {
      _log('md5 check $path failed: $e');
      return false;
    }
  }

  static Future<void> _mkdirSafe(FlipperClient client, String path) async {
    try {
      await client.storageMkdir(MkdirRequest(path: path));
    } catch (_) {}
  }
}

class _UpdateFile {
  _UpdateFile(this.name, this.data, this.md5);
  final String name;
  final List<int> data;
  final String md5;
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
      return l10n.firmwareErrorObReference;
    }
    if (obCompareMask?.length != size) {
      return l10n.firmwareErrorObMask;
    }
    if (obWriteMask?.length != size) {
      return l10n.firmwareErrorObWriteMask;
    }
    return null;
  }
}
