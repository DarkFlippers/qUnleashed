import 'package:flutter/material.dart';

import '../../services/guarded.dart';
import '../../services/localization/l10n.dart';
import '../../services/telemetry/settings.dart';
import '../../theme/theme.dart';

/// Tells the user once that failures are shared, and offers to stop.
///
/// [ADR 0013 §1](../../../docs/adr/0013-observability-with-sentry.md): a
/// notice and **not** a gate. Reporting is already running while this is on
/// screen, which is what makes it one — the app is usable behind it, and
/// dismissing it means the same as **Got it**.
///
/// Two actions. **Got it** closes it, and **Turn it off** closes it with the
/// switch off, because turning it off should take one tap at the moment the
/// user is being told rather than a hunt through Settings later.
///
/// No policy link. The repository has no privacy policy and this decision is
/// not waiting on one being written, so the notice carries the substance
/// instead: what is sent, what never is, and how to stop it. It gains the link
/// when there is one.
///
/// There is no onboarding flow to hang this on, so it is a sheet of its own.
/// Raised from `AppShell`'s first frame: not from `_initCore`, which must
/// never throw and has no UI, and not from `widgetMain()`, which has no window
/// at all — a headless isolate marking the notice shown is a user who never
/// sees it.
Future<void> showDiagnosticsNoticeIfDue(
  BuildContext context,
  DiagnosticsSettings settings,
) async {
  // The read is awaited rather than assumed: this runs on the first frame,
  // which can be ahead of the store opening. `load` memoises, so the switch
  // row asking later costs nothing.
  await settings.load();
  if (settings.noticeShown) return;
  if (!context.mounted) return;

  // Marked before it is shown, not after. §1 records it as shown either way,
  // and a swipe-dismiss returns the same `null` as a lost route — so waiting
  // for an answer is how this comes back at every launch for anyone who swipes
  // it away.
  //
  // Awaited, and it costs nothing: `load` above has already opened the
  // preference store, so the write finds it memoised. `guarded` rather than a
  // bare call because `persistSetting` catching everything is a property of
  // another file, and depending on it from here is how an unlabelled
  // `[uncaught]` gets added later. #23.
  await guarded(
    '[Diagnostics] recording that the notice was shown',
    settings.markNoticeShown,
  );
  if (!context.mounted) return;

  final turnOff = await showModalBottomSheet<bool>(
    context: context,
    // Dismissible, which is the whole difference between this and a gate.
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _DiagnosticsNoticeSheet(),
  );
  if (turnOff != true) return;
  await settings.setShareLogs(false);
}

class _DiagnosticsNoticeSheet extends StatelessWidget {
  const _DiagnosticsNoticeSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: colors.dialogBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.diagnosticsNoticeTitle,
              style: TextStyle(
                color: colors.dialogText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.diagnosticsNoticeBody,
              style: TextStyle(
                color: colors.dialogText,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    context.l10n.diagnosticsNoticeTurnOff,
                    style: TextStyle(color: colors.dialogMuted),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    context.l10n.commonGotIt,
                    style: TextStyle(color: colors.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
