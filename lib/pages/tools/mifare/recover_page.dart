import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/dialogs/confirm.dart';
import '../../../components/progress_button.dart';
import '../../../theme/theme.dart';
import 'cuid_dict_format.dart';
import 'recover_controller.dart';
import 'recover_models.dart';

class RecoverPage extends StatefulWidget {
  const RecoverPage({super.key});

  @override
  State<RecoverPage> createState() => _RecoverPageState();
}

class _RecoverPageState extends State<RecoverPage> {
  late final RecoverController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RecoverController()..addListener(_onChanged);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _confirmAbort() => QConfirmDialog.show(
    context,
    title: context.l10n.mfStopTitle,
    message: context.l10n.mfStopMessage,
    confirmLabel: context.l10n.mfStopConfirm,
    cancelLabel: context.l10n.mfStopCancel,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: !_controller.running,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmAbort() && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          title: Text(context.l10n.toolMifare),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBlock(
              state: _controller.state,
              totalUnits: _controller.totalUnits,
              doneUnits: _controller.doneUnits,
            ),
            ..._buildGroups(_controller),
          ],
        ),
      ),
    );
  }
}

/// Groups the flat entries by source → card (cuid) for the summary.
List<Widget> _buildGroups(RecoverController controller) {
  final entries = controller.entries;
  if (entries.isEmpty) return const [];

  final bySource = <RecoverSource, Map<int?, List<RecoverEntry>>>{};
  for (final entry in entries) {
    bySource
        .putIfAbsent(entry.source, () => <int?, List<RecoverEntry>>{})
        .putIfAbsent(entry.cuid, () => <RecoverEntry>[])
        .add(entry);
  }

  final widgets = <Widget>[];
  for (final source in RecoverSource.values) {
    final cards = bySource[source];
    if (cards == null) continue;
    widgets.add(_SourceHeader(source: source));
    for (final cardEntry in cards.entries) {
      widgets.add(
        _CardBlock(
          cuidHex: cardEntry.value.first.cuidHex,
          entries: cardEntry.value,
        ),
      );
    }
  }
  return widgets;
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({required this.source});

  final RecoverSource source;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (label, hint) = switch (source) {
      RecoverSource.reader => (
        context.l10n.mfSourceReader,
        context.l10n.mfSourceReaderHint,
      ),
      RecoverSource.tag => (
        context.l10n.mfSourceCard,
        context.l10n.mfSourceCardHint,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({required this.cuidHex, required this.entries});

  /// Null for entries no card can be attributed to; the block then renders
  /// its rows without a card heading.
  final String? cuidHex;
  final List<RecoverEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cuidHex != null) ...[
            Text(
              l10n.mfCardTitle(cuidHex!),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
          ],
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3),
              child: _EntryRow(entry: entry),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final RecoverEntry entry;

  static String _kindLabel(RecoverKind kind) => switch (kind) {
    RecoverKind.mfkey32 => 'mfkey32',
    RecoverKind.weakNested => l10n.mfKindWeakNested,
    RecoverKind.staticNonce => l10n.mfKindStaticNonce,
    RecoverKind.staticEncrypted => 'static-encrypted',
    RecoverKind.hardnested => 'hardnested',
    RecoverKind.corruptLog => l10n.mfKindCorruptLog,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final where = (entry.sectorName != null && entry.keyName != null)
        ? l10n.mfSectorKey('${entry.sectorName}', '${entry.keyName}')
        : null;

    final String line;
    String? explainer;
    Color color = colors.textPrimary;
    if (entry.key != null) {
      // isNew is decided at recovery time, so this tag is already correct while
      // the run is still in progress - not only in the final summary.
      final tag = entry.isNew == false
          ? l10n.mfTagAlreadyInDict
          : l10n.mfTagNew;
      line = '${where ?? ''} — ${entry.key}  [${_kindLabel(entry.kind)}, $tag]';
    } else if (entry.candidateCount != null && entry.cuid != null) {
      line = l10n.mfCandidateKeys(
        entry.candidateCount!,
        cuidDictFileName(entry.cuid!),
      );
      explainer = l10n.mfCandidateExplainer;
      color = colors.textMuted;
    } else {
      line = '${where != null ? '$where — ' : ''}${_kindLabel(entry.kind)}';
      color = colors.textMuted;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          line,
          style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace'),
        ),
        for (final sub in [explainer, entry.note])
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sub,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ),
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.state,
    required this.totalUnits,
    required this.doneUnits,
  });

  final RecoverState state;
  final int totalUnits;
  final int doneUnits;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Each recovery unit runs to completion with no sub-progress, and units vary
    // wildly in duration (a hardnested attack dwarfs an mfkey32 one), so a
    // percentage freezes between units and misleads. Instead the recovery bar
    // animates (liveness) and, when there is more than one unit, shows how many
    // are done. A null barText hides the bar (the terminal Saved / Error states).
    final (String title, String? barText, double? progress) = switch (state) {
      RecoverWaitingForDevice() => (l10n.mfConnecting, '…', null),
      RecoverDownloading(:final progress) => (
        l10n.mfDownloading,
        progress == null ? '…' : '${(progress * 100).round()}%',
        progress,
      ),
      RecoverCalculating() => (
        l10n.mfRecovering,
        totalUnits > 1 ? '$doneUnits / $totalUnits' : '…',
        null,
      ),
      RecoverUploading() => (l10n.mfSyncing, '…', null),
      RecoverSaved(:final keys, :final hasCandidates, :final hasFailures) => (
        _savedTitle(keys.length, hasCandidates, hasFailures),
        null,
        null,
      ),
      RecoverError(:final errorType) => (_errorText(errorType), null, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (barText != null)
          ProgressButton(
            text: barText,
            color: colors.accent,
            progressColor: colors.accent,
            progress: progress,
            indeterminate: progress == null,
            showPercent: false,
            height: 46,
          ),
      ],
    );
  }

  static String _savedTitle(int newKeys, bool hasCandidates, bool hadFailure) {
    final String base;
    if (newKeys > 0) {
      base = l10n.mfKeysAdded(newKeys);
    } else if (hasCandidates) {
      base = l10n.mfCandidatesSaved;
    } else if (hadFailure) {
      return l10n.mfFinishedWithErrors;
    } else {
      return l10n.mfNoNewKeys;
    }
    return hadFailure ? l10n.mfSomeStepsFailed(base) : base;
  }

  static String _errorText(RecoverErrorType type) => switch (type) {
    RecoverErrorType.notFoundFile => l10n.mfErrorNoLogs,
    RecoverErrorType.readWrite => l10n.mfErrorStorage,
    RecoverErrorType.flipperConnection => l10n.mfErrorNotConnected,
    RecoverErrorType.recoveryFailed => l10n.mfErrorUnexpected,
  };
}
