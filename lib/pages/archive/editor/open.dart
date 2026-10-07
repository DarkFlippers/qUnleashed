import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/notification.dart';
import '../../../components/path.dart';
import 'page.dart';

Future<bool> openLocalFileInEditor(
  BuildContext context, {
  required String localPath,
  String? title,
  Future<bool> Function(List<int> bytes)? onSave,
  String? Function()? onSaveFailureReason,
  VoidCallback? onRun,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => TextEditorPage(
        localPath: localPath,
        title: title,
        onSave: onSave,
        onSaveFailureReason: onSaveFailureReason,
        onRun: onRun,
      ),
    ),
  );
  return saved ?? false;
}

Future<bool> openRemoteFileInEditor(
  BuildContext context, {
  required String remotePath,
  required Future<String?> Function() download,
  required Future<bool> Function(List<int> bytes) upload,

  /// Why the last [download] or [upload] did not work. Both report through
  /// it: the one failure the user sees is whichever of the two just ran, and
  /// the controller keeps the reason for either. #110.
  String? Function()? failureReason,
  VoidCallback? onRun,
}) async {
  final String? localPath;
  try {
    localPath = await download();
  } on FlipperCancelledException {
    if (context.mounted) {
      context.showNotification(
        l10n.fmTransferCancelled,
        type: QNotificationType.warning,
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  if (localPath == null) {
    final reason = failureReason?.call();
    context.showNotification(
      reason == null || reason.isEmpty
          ? l10n.fmDownloadFailed
          : l10n.fmFailedBecause(l10n.fmDownloadFailed, reason),
      type: QNotificationType.error,
    );
    return false;
  }
  var cancelled = false;
  return openLocalFileInEditor(
    context,
    localPath: localPath,
    title: basename(remotePath),
    onSave: (bytes) async {
      cancelled = false;
      try {
        return await upload(bytes);
      } on FlipperCancelledException {
        cancelled = true;
        return false;
      }
    },
    onSaveFailureReason: () =>
        cancelled ? l10n.fmTransferCancelled : failureReason?.call(),
    onRun: onRun,
  );
}
