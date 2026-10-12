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
/// The two switches this screen draws, in the order it draws them.
///
/// An enum rather than two hand-written rows, because `GroupedCardList` keys
/// its separators and its corner rounding off the item list - so a second row
/// built outside it would be a card of its own rather than the second half of
/// one.
enum _Row {
  /// §1's switch. Everything else here is subordinate to it.
  share,

  /// §1's second switch: whether a replay of the seconds before a failure
  /// goes with it.
  replay,
}

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

  /// The same, for §1's second switch.
  ///
  /// Separate rather than a branch inside [_toggle], so each log line names
  /// one switch - "turning sharing off" and "turning replay off" are different
  /// facts about a user's privacy choice and a report carrying the wrong one
  /// is worse than a report carrying neither.
  void _toggleReplay(DiagnosticsSettings settings) {
    final next = !settings.shareReplay;
    guarded(
      '[Diagnostics] turning replay ${next ? 'on' : 'off'}',
      () => settings.setShareReplay(next),
    );
  }

  /// The rows on screen, which is not always both.
  ///
  /// The replay row is left out entirely while sharing is off rather than
  /// shown disabled: with nothing being sent there is nothing for a replay to
  /// be attached to, and a switch that does nothing is worse than a switch
  /// that is not there. `DiagnosticsSettings.shareReplay` keeps its value
  /// through that, so turning sharing back on restores the row where the user
  /// left it rather than at the default.
  List<_Row> _rows(DiagnosticsSettings settings) =>
      settings.shareLogs ? _Row.values : const [_Row.share];

  Widget _tile(BuildContext context, DiagnosticsSettings settings, _Row row) {
    final colors = context.appColors;
    final title = switch (row) {
      _Row.share => context.l10n.diagnosticsShareTitle,
      _Row.replay => context.l10n.diagnosticsReplayTitle,
    };
    final subtitle = switch (row) {
      _Row.share => context.l10n.diagnosticsShareSubtitle,
      _Row.replay => context.l10n.diagnosticsReplaySubtitle,
    };
    final value = switch (row) {
      _Row.share => settings.shareLogs,
      _Row.replay => settings.shareReplay,
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
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
                subtitle,
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
          value: value,
          activeThumbColor: colors.accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (_) => _tap(row, settings),
        ),
      ],
    );
  }

  /// Routes a tap on [row] to the switch it draws.
  ///
  /// One place, because the row is tappable in two ways - the card's own
  /// `onTap` and the `Switch` - and the two used to be the same expression
  /// written twice.
  void _tap(_Row row, DiagnosticsSettings settings) => switch (row) {
    _Row.share => _toggle(settings),
    _Row.replay => _toggleReplay(settings),
  };

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
          GroupedCardList<_Row>(
            items: _rows(settings),
            onTap: (row) =>
                () => _tap(row, settings),
            itemBuilder: (context, row) => _tile(context, settings, row),
          ),
        ],
      ),
    );
  }
}
