import 'package:flutter/material.dart';

import '../../../components/appbar.dart';
import '../../../components/cardlist.dart';
import '../../../components/clipboard.dart';
import '../../../components/dialogs/confirm.dart';
import '../../../services/build_identity.dart';
import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/logging.dart';
import '../../../services/telemetry/settings.dart';
import '../../../theme/theme.dart';
import '../diagnostics_scope.dart';

/// The reporting switch, and the log it is the remote half of.
///
/// Was the Log screen, renamed by ADR 0013 §1 when it gained the switch. The
/// two belong on one screen because they are the same thing from its two ends:
/// the log is what this device kept, and sharing is whether anyone else ever
/// sees it. Somebody who turns the switch off has not lost the route from "it
/// failed" to a bug report — it is the rest of this screen, and Copy still
/// hands them the same text Sentry would have received.
///
/// The log half is #89's. Errors survive a release build, but a buffer nobody
/// can open is the same as no buffer.
///
/// The list is a snapshot, deliberately: read when the page opens and on the
/// refresh action, not streamed. Someone reading a failure does not want the
/// lines moving under them, and the one thing they came to do is copy it.
class DiagnosticsSettingsPage extends StatefulWidget {
  const DiagnosticsSettingsPage({super.key});

  @override
  State<DiagnosticsSettingsPage> createState() =>
      _DiagnosticsSettingsPageState();
}

class _DiagnosticsSettingsPageState extends State<DiagnosticsSettingsPage> {
  List<String> _entries = LogService.history;

  void _reload() => setState(() => _entries = LogService.history);

  // Blank line between entries: an entry is a whole message, so joined with
  // one newline a stack trace's last frame sits flush against the next
  // timestamp and the paste reads as one run-on block.
  //
  // Opened with the build it came from (ADR 0014 §3). A log pasted into an
  // issue otherwise says nothing about which binary produced it, and the
  // version alone does not identify one: the number orders builds (§6) and the
  // commit names the tree, and a dev build's name carries neither.
  //
  // History is re-read *after* the await, not reused from the page's snapshot.
  // The first resolve of a session is what produces the `[caught] [Build]
  // version unavailable` line, so a paste built from the earlier snapshot would
  // show a header reading `unknown-dev` with the one line explaining why
  // guaranteed to be missing from it - a report that cannot name its own build
  // and gives no reason.
  Future<void> _copy() async {
    final stamp = await BuildIdentity.resolve();
    if (!mounted) return;
    final entries = LogService.history;
    await copyTextToClipboard(
      context,
      '${stamp.header}\n\n${entries.join('\n\n')}',
    );
  }

  Future<void> _clear() async {
    // Confirmed, unlike the Flibler console's clear, because this button sits
    // beside Copy and what it destroys is the only copy of the evidence.
    final ok = await QConfirmDialog.show(
      context,
      title: context.l10n.logClearTitle,
      message: context.l10n.logClearMessage,
      confirmLabel: context.l10n.commonClear,
    );
    // Dismissing the route resolves false, so the ordinary teardown leaves
    // above. What the mounted check catches is the narrow one: confirmed, then
    // the page disposed before this continuation runs. _reload is a setState,
    // and the analyzer cannot see it because it touches no BuildContext.
    if (!ok || !mounted) return;
    LogService.clearHistory();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsDiagnosticsTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
        actions: [
          QPageAppBarAction(
            tooltip: context.l10n.commonRefresh,
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          QPageAppBarAction(
            tooltip: context.l10n.commonCopy,
            // `guarded`, because the slot is a VoidCallback and the future
            // would otherwise be dropped. `resolve()` cannot reject today, so
            // this is not a live bare-unawaited violation - but depending on
            // that is how one gets added later, landing as `[uncaught]` with
            // nothing naming the operation. CLAUDE.md, #23.
            onPressed: _entries.isEmpty
                ? null
                : () => guarded('[Logs] copying the log', _copy),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          QPageAppBarAction(
            tooltip: context.l10n.commonClear,
            onPressed: _entries.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          _shareSwitch(context),
          if (_entries.isEmpty)
            Expanded(child: _empty(colors))
          else ...[
            _caution(colors),
            Expanded(child: _list(colors)),
          ],
        ],
      ),
    );
  }

  /// The one switch §1 asks for: on by default, sending by itself.
  ///
  /// Read through the scope rather than held in this page's state, so the row
  /// redraws when anything else changes it — the one-time notice's **Turn it
  /// off** being the case that matters, since that is dismissed over whatever
  /// screen is showing.
  ///
  /// Nothing here starts or stops the SDK. `Telemetry` listens to the same
  /// object, which is what keeps this file out of §2's import rule and keeps
  /// the switch testable without the SDK at all.
  Widget _shareSwitch(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GroupedCardList<DiagnosticsSettings>(
        items: [DiagnosticsScope.of(context)],
        onTap: (settings) =>
            () => _toggleShare(settings),
        itemBuilder: _shareTile,
      ),
    );
  }

  /// `guarded` for the same reason the Copy action uses it: the slots here are
  /// a [VoidCallback] and a `ValueChanged<bool>`, so the future would
  /// otherwise be dropped and a rejection would land as `[uncaught]` naming
  /// nothing. `setShareLogs` persists through `persistSetting`, which does not
  /// reject - CLAUDE.md and #23 are about not depending on that.
  ///
  /// Named for the state being moved *to*, so the log line reads as the thing
  /// that failed rather than as the thing that was true before it.
  void _toggleShare(DiagnosticsSettings settings) {
    final next = !settings.shareLogs;
    guarded(
      '[Diagnostics] turning sharing ${next ? 'on' : 'off'}',
      () => settings.setShareLogs(next),
    );
  }

  Widget _shareTile(BuildContext context, DiagnosticsSettings settings) {
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
          onChanged: (_) => _toggleShare(settings),
        ),
      ],
    );
  }

  Widget _empty(QAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          context.l10n.logEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  /// Says what the log can name, above the log itself.
  ///
  /// Absolute paths have the account name taken out of them at the sink, but
  /// that is the only category that can be removed mechanically: a message
  /// naming a card, a folder or a Flipper is not distinguishable from any
  /// other text. So the user is told, and the log is on screen to read, before
  /// the button that hands it to a public issue.
  Widget _caution(QAppColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: colors.info.withValues(alpha: 0.10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.logPrivacyCaution,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Oldest first, so reading down follows what happened. An entry is a whole
  /// message, stack trace included, which is why each is its own block.
  ///
  /// One [SelectionArea] around the list rather than a SelectableText per row:
  /// per-row selection cannot cross an entry boundary, which for a stack trace
  /// is the one thing anyone wants from it — and it spared every row a focus
  /// node and a selection overlay of its own.
  Widget _list(QAppColors colors) {
    final style = TextStyle(
      color: colors.terminalText,
      fontSize: 12,
      fontFamily: 'monospace',
      height: 1.4,
    );
    final divider = Divider(color: colors.divider, height: 18);
    return ColoredBox(
      color: colors.terminalBackground,
      child: SelectionArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          itemCount: _entries.length,
          separatorBuilder: (_, _) => divider,
          itemBuilder: (context, i) => Text(_entries[i], style: style),
        ),
      ),
    );
  }
}
