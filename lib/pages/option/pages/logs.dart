import 'package:flutter/material.dart';

import '../../../components/appbar.dart';
import '../../../components/dialogs/confirm.dart';
import '../../../components/share.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/logging.dart';
import '../../../theme/theme.dart';

/// Reads back what [LogService] kept.
///
/// The half of #89 that makes the rest of it worth anything. Errors survive a
/// release build now, but a buffer nobody can open is the same as no buffer —
/// and the app has no crash reporting, so this screen is the only route from
/// "it failed" to something a bug report can carry.
///
/// A snapshot, deliberately. The list is read when the page opens and on the
/// refresh action, not streamed: someone reading a failure does not want the
/// lines moving under them, and the one thing they came to do is copy it.
class LogSettingsPage extends StatefulWidget {
  const LogSettingsPage({super.key});

  @override
  State<LogSettingsPage> createState() => _LogSettingsPageState();
}

class _LogSettingsPageState extends State<LogSettingsPage> {
  List<String> _entries = LogService.history;

  void _reload() => setState(() => _entries = LogService.history);

  Future<void> _copy() async {
    // Blank line between entries: an entry is a whole message, so joined with
    // one newline a stack trace's last frame sits flush against the next
    // timestamp and the paste reads as one run-on block.
    await copyTextToClipboard(context, _entries.join('\n\n'));
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
    if (!ok) return;
    LogService.clearHistory();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsLogTitle),
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
            onPressed: _entries.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          QPageAppBarAction(
            tooltip: context.l10n.commonClear,
            onPressed: _entries.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _entries.isEmpty ? _empty() : _body(),
    );
  }

  Widget _empty() {
    final colors = context.appColors;
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

  Widget _body() => Column(
    children: [
      _caution(),
      Expanded(child: _list()),
    ],
  );

  /// Says what the log can name, above the log itself.
  ///
  /// Absolute paths have the account name taken out of them at the sink, but
  /// that is the only category that can be removed mechanically: a message
  /// naming a card, a folder or a Flipper is not distinguishable from any
  /// other text. So the user is told, and the log is on screen to read, before
  /// the button that hands it to a public issue.
  Widget _caution() {
    final colors = context.appColors;
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
  Widget _list() {
    final colors = context.appColors;
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
