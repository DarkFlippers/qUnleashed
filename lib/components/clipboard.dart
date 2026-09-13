import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/localization/l10n.dart';
import 'notification.dart';

/// Puts [text] on the clipboard and says so, or says why it did not go.
///
/// Copy-then-confirm was written out by hand at five places before this, and
/// had drifted: two raise the toast without a type, two do not await the write
/// at all. None of them reports a failure — the write is awaited inside a
/// callback whose own future is discarded, so a PlatformException becomes an
/// unhandled async error and the only signal is a toast that never appears.
///
/// That matters most where the payload is largest. Android carries a clipboard
/// write over a Binder transaction capped near a megabyte, so a big enough
/// text throws rather than truncating — and the biggest thing anyone copies is
/// the thing most worth having.
///
/// Not in `share.dart`, which is a leaf over `dart:io` and `pasteboard`:
/// putting this beside it would make every caller of `copyFileToClipboard`
/// drag in the notification overlay and the localization table.
Future<void> copyTextToClipboard(
  BuildContext context,
  String text, {
  String? message,
  QNotificationType type = QNotificationType.good,
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
    return;
  }
  if (!context.mounted) return;
  context.showNotification(message ?? context.l10n.commonCopied, type: type);
}
