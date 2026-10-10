import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/telemetry/settings.dart';
import '../../../theme/theme.dart';
import '../diagnostics_scope.dart';

/// The reporting switch, and nothing else.
///
/// This was the Log screen, then the Log screen plus a switch, and is now the
/// switch alone. ADR 0013 §1: Sentry is the only channel, so the in-memory
/// history, the Copy button, the Clear action and the caution above them are
/// gone with it. There is no longer a route from "it failed" to a bug report
/// that runs through the user, because there no longer needs to be — which was
/// the whole argument for the screen that used to be here.
///
/// A `StatelessWidget` for the same reason: the page held state only to keep a
/// snapshot of the log, and reads the switch through [DiagnosticsScope] so the
/// row redraws when anything else changes it — the one-time notice's **Turn it
/// off** being the case that matters, since that is dismissed over whatever
/// screen is showing.
///
/// What a user gives up is worth stating plainly, because it is real: with
/// reporting off, or in a build with no DSN, nothing records a failure that the
/// screen in front of them does not already name. The console still has it,
/// which is a developer's surface and not theirs.
class DiagnosticsSettingsPage extends StatelessWidget {
  const DiagnosticsSettingsPage({super.key});

  /// `guarded`, because the slots here are a [VoidCallback] and a
  /// `ValueChanged<bool>`, so the future would otherwise be dropped and a
  /// rejection would land as `[uncaught]` naming nothing. `setShareLogs`
  /// persists through `persistSetting`, which does not reject — CLAUDE.md and
  /// #23 are about not depending on that.
  ///
  /// Named for the state being moved *to*, so the log line reads as the thing
  /// that failed rather than as the thing that was true before it.
  void _toggle(DiagnosticsSettings settings) {
    final next = !settings.shareLogs;
    guarded(
      '[Diagnostics] turning sharing ${next ? 'on' : 'off'}',
      () => settings.setShareLogs(next),
    );
  }

  Widget _tile(BuildContext context, DiagnosticsSettings settings) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.l10n.diagnosticsShareTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10n.diagnosticsShareSubtitle,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: settings.shareLogs,
          activeThumbColor: colors.accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (_) => _toggle(settings),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = DiagnosticsScope.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsDiagnosticsTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          GroupedCardList<DiagnosticsSettings>(
            items: [settings],
            onTap: (s) =>
                () => _toggle(s),
            itemBuilder: _tile,
          ),
        ],
      ),
    );
  }
}
