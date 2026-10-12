import 'package:flutter/widgets.dart';

import '../../../components/archive/models/key.dart';
import '../../../components/dialogs/name.dart';
import '../../../services/localization/l10n.dart';
import 'controller.dart';
import 'failure_toast.dart';

/// Asks for a new name for [key] and renames it.
///
/// One function for what were two verbatim copies - the overview's and its
/// category page's - of a hand-rolled `showDialog<String>` that trimmed the
/// answer and checked nothing else, so a name with a `/` in it went to the
/// device and came back as "Could not rename" with no cause named. #277
///
/// Does nothing when the user dismisses the dialog, or answers with the name
/// the key already has. The failure is reported by [reportArchiveFailure], the
/// way every other action on a key reports one.
Future<void> promptRenameKey(
  BuildContext context, {
  required ArchiveController controller,
  required ArchiveKey key,
}) async {
  final newName = await QNameDialog.show(
    context,
    title: context.l10n.fmRename,
    initial: key.name,
    hintText: context.l10n.archiveFileName,
    confirmLabel: context.l10n.fmRename,
  );
  if (newName == null || newName == key.name || !context.mounted) return;

  await controller.renameKey(key, newName);
  if (!context.mounted) return;
  reportArchiveFailure(
    context,
    controller.lastFailure,
    context.l10n.archiveRenameFailed,
  );
}
