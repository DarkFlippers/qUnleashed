import 'package:flutter/widgets.dart';

import '../../../components/archive/models/key.dart';
import '../../../components/dialogs/name.dart';
import '../../../components/name_rule.dart';
import '../../../services/localization/l10n.dart';
import 'controller.dart';
import 'failure_toast.dart';

/// Asks for a new name for [key] and renames it.
///
/// One function for what were two verbatim copies - the overview's and its
/// category page's - neither of which checked the name. See
/// `deviceNameProblem` for the rule and #277 for the rest of the census.
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
    // The field holds a base name and the controller appends the extension,
    // so the budget leaves room for it - see `deviceNameBudgetFor`. Left at the
    // volume's own 255, a name right at the limit is approved on screen and
    // reaches `storageRename` four bytes over it: a refusal with no cause
    // named, which is the failure this prompt was wired up to remove.
    rule: NameRule.ofBytes(key.nameBudget),
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
