import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../theme.dart';
import '../../widgets/notification.dart';
import 'file_manager/controller.dart';

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
        isShareSupported ? 'Share' : 'Copy to clipboard',
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
        isShareSupported ? 'Share' : 'Copy to clipboard',
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
}) async {
  final localPath = await controller.downloadTo(remotePath);
  if (!context.mounted) return;
  if (localPath == null) {
    context.showNotification(
      'Download failed${controller.error != null ? ': ${controller.error}' : ''}',
      type: QNotificationType.error,
    );
    return;
  }

  await shareLocalFile(
    context,
    localPath,
    displayName: displayName ?? _basename(remotePath),
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
        'File not found: $localPath',
        type: QNotificationType.error,
      );
    }
    return;
  }

  final clipboardOk = await _copyFileToClipboard(file);

  if (!context.mounted) return;

  if (!isShareSupported) {
    context.showNotification(
      clipboardOk ? 'Copied to clipboard' : 'Clipboard unavailable',
      type: clipboardOk ? QNotificationType.good : QNotificationType.error,
    );
    return;
  }

  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null
      ? box.localToGlobal(Offset.zero) & box.size
      : null;

  try {
    await Share.shareXFiles(
      [XFile(localPath, name: displayName ?? _basename(localPath.replaceAll('\\', '/')))],
      sharePositionOrigin: origin,
    );
  } catch (e) {
    if (context.mounted) {
      context.showNotification(
        clipboardOk
            ? 'Copied to clipboard (share failed: $e)'
            : 'Share failed: $e',
        type: clipboardOk ? QNotificationType.warning : QNotificationType.error,
      );
    }
    return;
  }

  if (!context.mounted) return;
  context.showNotification(
    clipboardOk
        ? 'Shared and copied to clipboard'
        : 'Shared (clipboard unavailable)',
    type: QNotificationType.good,
  );
}

bool get _supportsClipboardFileUri =>
    io.Platform.isWindows ||
    io.Platform.isLinux ||
    io.Platform.isMacOS;

Future<bool> _copyFileToClipboard(io.File file) async {
  if (!_supportsClipboardFileUri) return false;
  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;
    final uri = file.absolute.uri;
    final item = DataWriterItem(suggestedName: _basename(file.path.replaceAll('\\', '/')))
      ..add(Formats.fileUri(uri));
    await clipboard.write([item]);
    return true;
  } catch (_) {
    return false;
  }
}

String _basename(String path) {
  final idx = path.lastIndexOf('/');
  return idx < 0 ? path : path.substring(idx + 1);
}
