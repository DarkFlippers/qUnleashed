import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/telemetry/settings.dart';
import '../../../theme/theme.dart';
import '../diagnostics_scope.dart';

/// The two reporting switches, and nothing else.
///
/// This was the Log screen, then the Log screen plus a switch, and is now two
/// switches. ADR 0013 §1: Sentry is the only channel, so the in-memory
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

  /// The rows to draw, which is both switches only when the second one can do
  /// something.
  ///
  /// The replay row is dropped with sharing off, because there is then nothing
  /// for a replay to be attached to, and dropped where
  /// [DiagnosticsSettings.replaySupported] is false, because the recorder does
  /// not exist there. Both are the same judgement: a switch that does nothing
  /// is worse than no switch. The stored value survives either, so a user who
  /// turns sharing back on - or opens the same build on a phone - finds the
  /// choice they made rather than the default.
  ///
  /// A [_Toggle] list and not an enum with a switch per field, which is what
  /// this was: three `switch (row)` expressions for title, subtitle and value
  /// are exhaustive but not *tied together*, so a row could take another row's
  /// subtitle and still compile. `device.dart` and `push.dart` in this folder
  /// already carry this shape.
  ///
  /// `guarded` in each `onChanged`, because `GroupedCardList`'s slots are a
  /// [VoidCallback] and a `ValueChanged<bool>` - the future would otherwise be
  /// dropped and a rejection would land as `[uncaught]` naming nothing.
  /// `persistSetting` does not reject; CLAUDE.md and #23 are about not
  /// depending on that. One line per switch, named for the state being moved
  /// *to*: "turning sharing off" and "turning replay off" are different facts
  /// about a privacy choice, and a report carrying the wrong one is worse than
  /// one carrying neither.
  List<_Toggle> _toggles(BuildContext context, DiagnosticsSettings settings) {
    final l10n = context.l10n;
    return [
      _Toggle(
        title: l10n.diagnosticsShareTitle,
        subtitle: l10n.diagnosticsShareSubtitle,
        value: settings.shareLogs,
        onChanged: (next) => guarded(
          '[Diagnostics] turning sharing ${next ? 'on' : 'off'}',
          () => settings.setShareLogs(next),
        ),
      ),
      if (settings.shareLogs && DiagnosticsSettings.replaySupported)
        _Toggle(
          title: l10n.diagnosticsReplayTitle,
          subtitle: l10n.diagnosticsReplaySubtitle,
          value: settings.shareReplay,
          onChanged: (next) => guarded(
            '[Diagnostics] turning replay ${next ? 'on' : 'off'}',
            () => settings.setShareReplay(next),
          ),
        ),
    ];
  }

  Widget _tile(BuildContext context, _Toggle row) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                row.title,
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
                row.subtitle,
                // Six and not four: the replay subtitle has to say that
                // recording is continuous *and* what is hidden from it, and
                // the second half is the one a user needs. Four lines fit the
                // English and ellipsised the masking clause out of a longer
                // translation.
                maxLines: 6,
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
          value: row.value,
          activeThumbColor: colors.accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: row.onChanged,
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
          GroupedCardList<_Toggle>(
            items: _toggles(context, settings),
            // The card and the `Switch` are two ways to tap one row, and this
            // is what keeps them one expression.
            onTap: (row) =>
                () => row.onChanged(!row.value),
            itemBuilder: (context, row) => _tile(context, row),
          ),
        ],
      ),
    );
  }
}

/// One switch row on this screen.
///
/// The same shape as `device.dart`'s and `push.dart`'s `_Toggle`, which is the
/// folder's answer to "several switch rows inside one `GroupedCardList`" -
/// that widget keys its separators and its corner rounding off the item list,
/// so a row built outside the list would be a card of its own.
class _Toggle {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Takes the state being moved *to*, so both callers - the card's `onTap`
  /// and the `Switch` - pass the same thing and neither has to know the
  /// current value twice.
  final void Function(bool next) onChanged;
}
