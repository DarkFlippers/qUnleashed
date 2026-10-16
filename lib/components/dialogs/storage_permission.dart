import 'package:flutter/material.dart';

import '../../services/guarded.dart';
import '../../services/localization/l10n.dart';
import '../../services/permissions/permission.dart';
import '../../services/permissions/scope.dart';
import '../../services/storage/asked_store.dart';
import '../../services/storage/permissions.dart';
import '../../theme/theme.dart';
import '../permission_notice.dart';

/// Explains what storage access is for, then opens the screen that grants it.
///
/// The "ask in context, never at launch" half of #351. Storage is requested
/// today on the first file call, before the user knows what it is for — and
/// `MANAGE_EXTERNAL_STORAGE` does not raise a dialog, it drops the user into a
/// full system settings list of every installed app. Unannounced that is
/// bewildering, and a user who backs out of it has refused something nobody
/// told them about.
///
/// So the explainer goes first, every time, and it names the three steps the
/// system screen will ask for. This is the one action behind every storage
/// notice in the app — the IR library dialog, Archive, Settings → Storage —
/// rather than each one inventing its own copy.
///
/// Raises the system prompt if this install has never seen it, and otherwise
/// opens app settings.
///
/// Both routes matter. The first ask is what the explainer announces, and
/// `MANAGE_EXTERNAL_STORAGE`'s own request *is* the all-files-access screen,
/// so it lands the user where the three steps above describe. Once the prompt
/// has been shown, `ensureAndroidStoragePermission` will not raise it again in
/// this process and the permission is reversible only in settings, so there is
/// nothing left to re-ask and app settings is the only place to send them.
///
/// Nothing is returned. The outcome reaches `PermissionCenter` through the
/// storage sink and the resume re-read, which is what clears the notice
/// without a restart — waiting here for an answer the settings screen never
/// gives would mean guessing at one.
///
/// [center] is told directly on the ask path so the gate clears the moment the
/// answer is known, rather than on the next resume.
Future<void> promptStorageAccess(BuildContext context) {
  // Wrapped whole, so the future handed to a tap handler provably cannot
  // reject. Everything inside is already guarded or catches its own except
  // `showDialog`, and three call sites drop this future into a
  // `VoidCallback` - exactly the shape that lands in the log as an
  // unlabelled `[uncaught]` naming no operation. #23.
  return guarded(
    '[Permissions] the storage access flow',
    () => _promptStorageAccess(context),
  );
}

Future<void> _promptStorageAccess(BuildContext context) async {
  final center = PermissionScope.maybeOf(context);
  final proceed = await showDialog<bool>(
    context: context,
    builder: (_) => const _StorageAccessExplainer(),
  );
  if (proceed != true) return;
  final asked = await storageAskedStore.wasAsked();
  if (!asked) {
    // The outcome is captured inside the task rather than returned by
    // `guarded`, which answers `Future<void>` by design. Guarded at all
    // because a plugin that throws here would otherwise reject into the zone
    // as an unlabelled `[uncaught]`. #23.
    PermissionOutcome? outcome;
    await guarded('[Permissions] asking for storage access', () async {
      outcome = await askForAndroidStoragePermission();
    });
    final answered = outcome;
    // Recorded here as well as through the sink, so the gate clears the
    // moment the answer is known rather than on the next resume.
    if (answered != null) center?.record(AppPermission.storage, answered);
    return;
  }
  if (!context.mounted) return;
  await openPermissionSettings(context, '[Permissions] opening app settings');
}

class _StorageAccessExplainer extends StatelessWidget {
  const _StorageAccessExplainer();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      content: SizedBox(
        width: 340,
        // Scrollable, and for the reason `diagnostics_notice.dart` records:
        // every translation of these strings is longer than the English, and
        // a fixed column overflowed that notice by 15 px on a short window.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              permissionBadge(
                icon: Icons.folder_outlined,
                tone: colors.accent,
                size: 88,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.permissionStorageTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.dialogText,
                  fontSize: 18,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.permissionStorageWhy,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.dialogMuted,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: colors.dialogDivider),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.permissionStorageStepsTitle,
                  style: TextStyle(
                    color: colors.dialogText,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Numbered in the strings rather than by a widget: the order is
              // part of the sentence a translator reads, and three ARB keys
              // are easier to review than one with embedded markup.
              _step(colors, '1', l10n.permissionStorageStepFind),
              _step(colors, '2', l10n.permissionStorageStepAllow),
              _step(colors, '3', l10n.permissionStorageStepReturn),
              const SizedBox(height: 14),
              Text(
                l10n.permissionStorageDeclineNote,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.dialogMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            context.l10n.permissionNotNow,
            style: TextStyle(color: colors.dialogMuted),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.accent),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.permissionContinue),
        ),
      ],
    );
  }

  Widget _step(QAppColors colors, String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$number.',
              style: TextStyle(
                color: colors.dialogMuted,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colors.dialogMuted,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
