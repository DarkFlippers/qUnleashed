import '../../../services/localization/l10n.dart';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../components/path.dart';
import '../../../components/share.dart';
import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import 'controller.dart';

bool get isShareSupported =>
    io.Platform.isAndroid || io.Platform.isIOS || io.Platform.isMacOS;

class ShareRemoteFileTile extends StatelessWidget {
  const ShareRemoteFileTile({
    super.key,
    required this.controller,
    required this.remotePath,
    this.displayName,
    this.onStarted,
  });

  final FileManagerController controller;
  final String remotePath;
  final String? displayName;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListTile(
      leading: Icon(
        isShareSupported ? Icons.ios_share : Icons.content_copy,
        color: colors.textPrimary,
      ),
      title: Text(
        isShareSupported ? l10n.shareShare : l10n.shareCopyToClipboard,
        style: TextStyle(color: colors.textPrimary),
      ),
      onTap: () {
        onStarted?.call();
        shareRemoteFile(
          context,
          controller,
          remotePath,
          displayName: displayName,
        );
      },
    );
  }
}

class ShareLocalFileTile extends StatelessWidget {
  const ShareLocalFileTile({
    super.key,
    required this.localPath,
    this.displayName,
    this.onStarted,
  });

  final String localPath;
  final String? displayName;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListTile(
      leading: Icon(
        isShareSupported ? Icons.ios_share : Icons.content_copy,
        color: colors.textPrimary,
      ),
      title: Text(
        isShareSupported ? l10n.shareShare : l10n.shareCopyToClipboard,
        style: TextStyle(color: colors.textPrimary),
      ),
      onTap: () {
        onStarted?.call();
        shareLocalFile(context, localPath, displayName: displayName);
      },
    );
  }
}

Future<void> shareRemoteFile(
  BuildContext context,
  FileManagerController controller,
  String remotePath, {
  String? displayName,
  int expectedSize = 0,
}) async {
  final localPath = await controller.downloadTo(
    remotePath,
    expectedSize: expectedSize,
  );
  if (!context.mounted) return;
  if (localPath == null) {
    context.showNotification(
      l10n.shareDownloadFailed(controller.error != null ? ': ${controller.error}' : ''),
      type: QNotificationType.error,
    );
    return;
  }

  await shareLocalFile(
    context,
    localPath,
    displayName: displayName ?? basename(remotePath),
  );
}

Future<void> shareLocalFile(
  BuildContext context,
  String localPath, {
  String? displayName,
}) async {
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

  try {
    await Share.shareXFiles([
      XFile(
        localPath,
        name: displayName ?? basename(localPath.replaceAll('\\', '/')),
      ),
    ], sharePositionOrigin: origin);
  } catch (e) {
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
  context.showNotification(
    clipboardOk
        ? l10n.shareSharedAndCopied
        : l10n.shareSharedNoClipboard,
    type: QNotificationType.good,
  );
}
