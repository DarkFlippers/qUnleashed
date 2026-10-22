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

  /// What to say when [download] or [upload] ended in that cancel; null says
  /// nothing.
  ///
  /// Called only while [context] is still mounted. The implementations are
  /// State methods that word themselves off their own `context`, and
  /// `State.context` after dispose throws - see the catch below. Both call
  /// sites in here check before calling, and a third would have to as well.
  String? Function(FlipperCancelledException cancel)? cancelledMessage,
  VoidCallback? onRun,
}) async {
  final String? localPath;
  try {
    localPath = await download();
  } on FlipperCancelledException catch (e) {
    // Mounted first, and not merely before the notification: [cancelledMessage]
    // belongs to a State, and the one in the file manager reads `context.l10n`
    // to word itself. Reading `State.context` after dispose throws either way -
    // debug asserts with "This widget has been unmounted", and release, where
    // that assert is stripped, dereferences a null `_element` and raises the
    // TypeError the user actually hit.
    //
    // It is not loud when it happens: the tap runs inside
    // `guarded('[FileManager] open ...')`, so the throw is swallowed there and
    // the whole open is abandoned - no cancel notification, and the refresh
    // after it never runs. A download the user walked away from is exactly
    // when that happens. QUNLEASHED-1F, and
    // `test/editor_cancel_after_dispose_test.dart` keeps the order honest.
    if (!context.mounted) return false;
    final message = cancelledMessage?.call(e);
    if (message != null) {
      context.showNotification(message, type: QNotificationType.warning);
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
      // `failureReason` reads a controller rather than a context, so it
      // answers whether or not the page that opened this is still there.
      if (cancel == null) return failureReason?.call();
      // [cancelledMessage] does read a context, so it needs the same check as
      // the catch above. This is not the unreachable half of it: the editor is
      // pushed onto the root navigator rather than above a nested one, so it
      // outlives the page that opened it whenever the shell drops that page -
      // `_page` swaps a file manager for `SizedBox.shrink()` on a wide ->
      // narrow change (`app/shell.dart`), which a desktop window resize does
      // while the editor is still on screen.
      //
      // Null rather than falling back to `failureReason`: a cancel does not
      // set `lastFailure`, so that would word this save with some earlier
      // operation's reason.
      if (!context.mounted) return null;
      return cancelledMessage?.call(cancel);
    },
    onRun: onRun,
  );
}
