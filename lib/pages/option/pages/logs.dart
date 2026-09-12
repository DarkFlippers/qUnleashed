import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/notification.dart';
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
  late List<String> _entries = LogService.history;

  void _reload() => setState(() => _entries = LogService.history);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _entries.join('\n')));
    if (!mounted) return;
    context.showNotification(
      context.l10n.logCopied,
      type: QNotificationType.good,
    );
  }

  void _clear() {
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
          IconButton(
            tooltip: context.l10n.commonRefresh,
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: context.l10n.logCopy,
            onPressed: _entries.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: context.l10n.commonClear,
            onPressed: _entries.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _entries.isEmpty ? _empty(colors) : _list(colors),
    );
  }

  Widget _empty(QAppColors colors) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        context.l10n.logEmpty,
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.textMuted, fontSize: 14, height: 1.5),
      ),
    ),
  );

  /// Oldest first, so reading down follows what happened. An entry is a whole
  /// message, stack trace included, which is why each is its own selectable
  /// block rather than a line in one long run of text.
  Widget _list(QAppColors colors) => ListView.separated(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    itemCount: _entries.length,
    separatorBuilder: (_, _) => Divider(color: colors.divider, height: 18),
    itemBuilder: (context, i) => SelectableText(
      _entries[i],
      style: TextStyle(
        color: colors.textSecondary,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.4,
      ),
    ),
  );
}
