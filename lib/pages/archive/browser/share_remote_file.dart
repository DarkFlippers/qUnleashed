import '../../../services/localization/l10n.dart';

import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../components/share.dart';
import '../../../components/notification.dart';
import '../../../services/logging.dart';
import 'controller.dart';

bool get isShareSupported =>
    io.Platform.isAndroid || io.Platform.isIOS || io.Platform.isMacOS;

Future<void> shareRemoteFile(
  BuildContext context,
  FileManagerController controller,
  String remotePath, {
  int expectedSize = 0,
}) async {
  final String? localPath;
  try {
    localPath = await controller.downloadTo(
      remotePath,
      expectedSize: expectedSize,
    );
  } on FlipperCancelledException catch (e) {
    if (context.mounted && controller.cancelAcknowledged(e)) {
      context.showNotification(
        l10n.fmTransferCancelled,
        type: QNotificationType.warning,
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (localPath == null) {
    context.showNotification(
      l10n.shareDownloadFailed(
        controller.error != null ? ': ${controller.error}' : '',
      ),
      type: QNotificationType.error,
    );
    return;
  }

  await shareLocalFile(context, localPath);
}

Future<void> shareLocalFile(BuildContext context, String localPath) async {
  final file = io.File(localPath);
  if (!await file.exists()) {
    if (context.mounted) {
      context.showNotification(
        l10n.shareFileNotFound(localPath),
        type: QNotificationType.error,
      );
    }
    return;
  }

  final clipboardOk = await copyFileToClipboard(file.path);

  if (!context.mounted) return;

  if (!isShareSupported) {
    context.showNotification(
      clipboardOk ? l10n.shareCopied : l10n.shareClipboardUnavailable,
      type: clipboardOk ? QNotificationType.good : QNotificationType.error,
    );
    return;
  }

  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

  // No name is passed, because on these three platforms there is nowhere to
  // put one. The share sheet is handed `paths` and `mimeTypes` and nothing
  // else (`MethodChannelShare._toPlatformMap`), so what the receiving app
  // shows is the last segment of the path. Both of the parameters that look
  // like they set it are inert for a path-backed file: `XFile(path, name:)`
  // throws `name` away in `cross_file`'s io constructor - its own doc says the
  // parameter "exists only to match the web version" - and `fileNameOverrides`
  // is read only where `_getFile` builds a temp file from bytes, which it skips
  // the moment `file.path.isNotEmpty`. An earlier version of this call passed
  // both in turn and neither ever reached a device.
  //
  // Nothing is lost by that, because the path already carries the right name:
  // `shareRemoteFile` shares what `_downloadToCache` wrote under
  // `basename(remotePath)`, and the key sheet shares the key's own file. To
  // control the name deliberately one would have to write the bytes out under
  // it, or pass `XFile.fromData`; `ArchiveKey.name` in particular would be the
  // wrong thing to pass, since it is the name *without* the extension.
  final ShareResult result;
  try {
    result = await SharePlus.instance.share(
      ShareParams(files: [XFile(localPath)], sharePositionOrigin: origin),
    );
  } catch (e, stack) {
    // Logged before the `mounted` check, and at `caught` rather than `info`:
    // the user can walk away while the sheet is up, and then the notification
    // below is skipped and this is the only record there is. The causes worth
    // seeing are ours - a `FileUriExposedException` for a path outside the
    // Android file provider, or the `ArgumentError` that `ShareParams`
    // validation throws.
    LogService.caught(
      '[Share] sharing $localPath failed: ${LogService.describe(e, stack)}',
    );
    if (context.mounted) {
      context.showNotification(
        clipboardOk
            ? l10n.shareCopiedShareFailed('$e')
            : l10n.shareFailed('$e'),
        type: clipboardOk ? QNotificationType.warning : QNotificationType.error,
      );
    }
    return;
  }

  if (!context.mounted) return;

  // `share` reports a dismissal and a missing result by *returning*, not by
  // throwing, so a `catch` alone cannot tell them from a success - which is how
  // tapping outside the sheet, or double-tapping Share on Android (the plugin
  // answers `unavailable` to a second call while one is pending), used to be
  // reported as "Shared".
  switch (result.status) {
    case ShareResultStatus.success:
      context.showNotification(
        clipboardOk ? l10n.shareSharedAndCopied : l10n.shareSharedNoClipboard,
        type: QNotificationType.good,
      );
    case ShareResultStatus.dismissed:
      // The user changed their mind. Not a success and not a failure, so the
      // copy is the only thing left worth saying.
      if (clipboardOk) {
        context.showNotification(
          l10n.shareCopied,
          type: QNotificationType.good,
        );
      }
    case ShareResultStatus.unavailable:
      // The sheet ran and the platform will not say what came of it. Say
      // nothing rather than claim it went out, and keep the raw answer.
      LogService.caught(
        '[Share] no share result for $localPath: ${result.raw}',
      );
      if (clipboardOk) {
        context.showNotification(
          l10n.shareCopied,
          type: QNotificationType.good,
        );
      }
  }
}
