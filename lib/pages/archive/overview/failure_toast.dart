import 'package:flutter/widgets.dart';

import '../../../components/notification.dart';
import '../../../services/localization/l10n.dart';

/// Tells the user why the thing they just asked for did not happen.
///
/// [reason] is `ArchiveController.lastFailure` - null when the operation
/// worked, which is why every call site reads it straight after the await
/// rather than checking a bool that does not exist. The operations here
/// return void, and the controller's other error field is cleared by the
/// refresh each of them ends with, so until this existed a rename, a delete
/// or a restore that failed reached nobody at all. #110.
///
/// Shared because the archive has four screens that drive the same handful of
/// operations, and a rename dialog that exists twice.
void reportArchiveFailure(
  BuildContext context,
  String? reason,
  String message,
) {
  if (reason == null || reason.isEmpty) return;
  context.showNotification(
    context.l10n.fmFailedBecause(message, reason),
    type: QNotificationType.error,
  );
}
