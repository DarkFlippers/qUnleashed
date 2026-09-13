import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pasteboard/pasteboard.dart';

import '../services/localization/l10n.dart';
import 'notification.dart';

/// Only desktop clipboards carry file references; on mobile a pasted file URI
/// is meaningless, so callers fall back to the share sheet there.
bool get supportsClipboardFileUri =>
    io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;

/// Copies the file at [path] to the system clipboard as a file reference
/// (paste-as-file on desktop). Returns false when the platform or the
/// clipboard cannot carry one.
Future<bool> copyFileToClipboard(String path) async {
  if (!supportsClipboardFileUri) return false;
  try {
    return await Pasteboard.writeFiles([io.File(path).absolute.path]);
  } catch (_) {
    return false;
  }
}

/// Puts [text] on the clipboard and says so, or says why it did not go.
///
/// Copy-then-confirm was written out by hand at six call sites and had already
/// drifted — one without the type, one without an await, one on a different
/// notification helper. The drift matters most on the failure side: every one
/// of them discards the future, so a PlatformException became an unhandled
/// async error and the user's only signal was the absence of a toast.
///
/// Android carries a clipboard write over a Binder transaction capped near a
/// megabyte, so a large enough payload throws rather than truncating — which
/// is exactly the case worth reporting, since the biggest thing anyone copies
/// is the thing most worth having.
Future<bool> copyTextToClipboard(
  BuildContext context,
  String text, {
  String? message,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (e) {
    if (context.mounted) {
      context.showNotification(
        context.l10n.commonCopyFailed('$e'),
        type: QNotificationType.error,
      );
    }
    return false;
  }
  if (context.mounted) {
    context.showNotification(
      message ?? context.l10n.commonCopied,
      type: QNotificationType.good,
    );
  }
  return true;
}
