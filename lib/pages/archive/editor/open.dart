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

  /// Whether the firmware acknowledged the cancel that ended [download] or
  /// [upload]. False, or absent, says nothing to the user: the transfer left
  /// the screen, but nothing claims it stopped.
  ///
  /// A predicate rather than the wording, so that nothing here depends on a
  /// caller's `BuildContext` outliving the transfer. It used to be
  /// `String? Function(...)`, every implementation was a State method wording
  /// itself off `context.l10n`, and a cancel that landed after the user left
  /// the page read `State.context` on a disposed State: an assert in debug,
  /// and in release a null `_element` dereference that `guarded` swallowed,
  /// taking the whole open with it. QUNLEASHED-1F. The string is a constant,
  /// so it is read here from the context-free [l10n] instead - the same shape
  /// `shareRemoteFile` already uses for this exact cancel.
  bool Function(FlipperCancelledException cancel)? cancelAcknowledged,
  VoidCallback? onRun,
}) async {
  final String? localPath;
  try {
    localPath = await download();
  } on FlipperCancelledException catch (e) {
    // An ordinary don't-toast-a-dead-context check, which is all it has to be
    // now that the wording does not come from one. `test/
    // editor_cancel_after_dispose_test.dart` covers the cancel that lands
    // after the page has gone.
    if (context.mounted && (cancelAcknowledged?.call(e) ?? false)) {
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
  FlipperCancelledException? cancelled;
  return openLocalFileInEditor(
    context,
    localPath: localPath,
    title: basename(remotePath),
    onSave: (bytes) async {
      cancelled = null;
      try {
        return await upload(bytes);
      } on FlipperCancelledException catch (e) {
        cancelled = e;
        return false;
      }
    },
    onSaveFailureReason: () {
      final cancel = cancelled;
      if (cancel == null) return failureReason?.call();
      // Not `failureReason` as the fallback: a cancel does not set
      // `lastFailure`, so that would word this save with some earlier
      // operation's reason.
      //
      // Neither half reads a context, which is what lets this answer at all.
      // The editor sits on the root navigator, so it outlives the page that
      // opened it whenever the shell drops that page - `_page` swaps a file
      // manager for `SizedBox.shrink()` on a wide -> narrow change
      // (`app/shell.dart`), which a desktop window resize does with the editor
      // still on screen. The user is looking at the editor and deserves the
      // reason regardless.
      return (cancelAcknowledged?.call(cancel) ?? false)
          ? l10n.fmTransferCancelled
          : null;
    },
    onRun: onRun,
  );
}
