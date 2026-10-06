import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/dialogs/confirm.dart';
import '../../../components/progress_button.dart';
import '../../../theme/theme.dart';
import 'cuid_dict_format.dart';
import 'existed_keys_storage.dart';
import 'recover_controller.dart';
import 'recover_models.dart';

import 'package:flipperlib/flipperlib.dart';

class RecoverPage extends StatefulWidget {
  const RecoverPage({super.key, required this.client, this.createController});

  /// The Flipper this run belongs to. Required rather than defaulted: the
  /// route builder is handed a context with a DeviceScope above it, so a
  /// default would only hide which device a recovery ran against. ADR 0002.
  final FlipperClient client;

  /// Builds the controller this page drives.
  ///
  /// A seam, and only that: the page still owns what it gets back and disposes
  /// it. Without one there is no way to reach a finished run in a test, because
  /// the controller is built here and would bring the four native recoverers
  /// with it - and the states worth asserting about (a run that was stopped, a
  /// run that failed) are precisely the ones reached by what those recoverers
  /// do. ADR 0002.
  final RecoverController Function(FlipperClient client)? createController;

  @override
  State<RecoverPage> createState() => _RecoverPageState();
}

class _RecoverPageState extends State<RecoverPage> {
  late final RecoverController _controller;

  @override
  void initState() {
    super.initState();
    final build =
        widget.createController ??
        (client) => RecoverController(client: client);
    _controller = build(widget.client)..addListener(_onChanged);
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

  /// Stops the run without leaving the page.
  ///
  /// Behind the same confirmation as backing out: those strings ask only
  /// whether to stop, not what becomes of the keys, so they are honest for
  /// both. The outcomes are not the same - this keeps what the run has found
  /// and leaving does not - which is the reason the button exists. Until it
  /// did, the engine's Stop was reachable only by popping the page, so the only
  /// way to interrupt an attack was to discard every key it had recovered.
  ///
  /// Disabled rather than hidden once asked for: a hardnested bucket can take a
  /// moment to reach its next check, and a button that vanishes mid-tap reads
  /// as a misfire.
  /// `danger`, because stopping is the destructive half of a running job -
  /// matching how [QConfirmDialog] tints the Stop it puts behind this. That is
  /// the substantive change: an OutlinedButton's default foreground is already
  /// `colorScheme.primary`, i.e. accent, so what moves here is accent to
  /// danger, the border (which did come from an un-overridden
  /// `ColorScheme.outline`), the disabled pair, and the text metrics.
  Widget _stopButton(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton(
        onPressed: _controller.cancelled
            ? null
            : () async {
                if (await _confirmAbort()) _controller.stop();
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.danger,
          disabledForegroundColor: colors.textMuted,
          side: BorderSide(
            color: _controller.cancelled ? colors.divider : colors.danger,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          context.l10n.mfStopConfirm,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

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
            _StatusBlock(controller: _controller),
            if (_controller.canStop) _stopButton(context),
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
  const _StatusBlock({required this.controller});

  final RecoverController controller;

  RecoverState get state => controller.state;
  int get totalUnits => controller.totalUnits;
  int get doneUnits => controller.doneUnits;

  /// Keys this run derived that are still listed below and not on the device.
  /// A key the dictionary already held is not at risk and does not count.
  /// Computed here rather than on every build, since only an error reads it.
  int get _recoveredThisRun =>
      controller.entries.where((e) => e.key != null && e.isNew == true).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A recovery unit runs to completion with no sub-progress, and units vary
    // wildly in duration (a hardnested attack dwarfs an mfkey32 one), so a
    // percentage freezes between units and misleads. Instead the recovery bar
    // animates (liveness) and, when there is more than one unit, shows how many
    // are done. A null barText hides the bar (the terminal Saved / Error states).
    //
    // The two transfers are the exception and do carry a percentage: both know
    // their size up front, and both are long enough on a slow link that an
    // animated bar alone reads as a hang rather than as work.
    final (String title, String? barText, double? progress) = switch (state) {
      RecoverWaitingForDevice() => (l10n.mfConnecting, '…', null),
      RecoverDownloading(:final progress) => (
        l10n.mfDownloading,
        _percent(progress),
        progress,
      ),
      // The unit counter always shows: it is the only run-level progress there
      // is, and a phase that can measure itself adds a percentage rather than
      // replacing it.
      RecoverCalculating(:final label, :final fraction) => (
        label ?? l10n.mfRecovering,
        _calculatingBar(fraction),
        fraction,
      ),
      RecoverUploading(:final progress) => (
        l10n.mfSyncing,
        _percent(progress),
        progress,
      ),
      RecoverSaved(
        :final keys,
        :final hasCandidates,
        :final hasFailures,
        :final stopped,
      ) =>
        (
          _savedTitle(keys.length, hasCandidates, hasFailures, stopped),
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
        // First, because it changes what every line under it means: "no new
        // keys" after a Stop is a statement about two sectors, not twelve.
        // Without it a part-finished run and a complete one read identically.
        // Only once a plan exists. A Stop during the download has no steps to
        // have got through, and the headline already says so.
        if (state case RecoverSaved(stopped: true)) ...[
          if (totalUnits > 0)
            _Footnote(l10n.mfStoppedEarly(controller.doneUnits, totalUnits)),
          // The way back. A Stop lands in the same terminal state a finished
          // run does, which offered nothing to press - so the only way to run
          // again was to leave the page and come back, since that is what
          // builds a fresh controller and starts it. Nothing in the controller
          // needed changing: _run() clears _cancelled before it does anything
          // else, which is what makes a second start safe.
          //
          // Restart, never resume. The engine keeps no checkpoint - a stopped
          // attack frees its candidate statelists and the Sum(a8) guess it was
          // working through is recorded nowhere - so continuing is not a thing
          // that can be offered, and a button promising it would lie.
          _again(context, controller.start),
        ],
        // The run is only half done when candidates were written: the Flipper
        // has to try them against the card itself, and nothing said so. A user
        // who does not know that reads "saved" as "finished".
        if (state case RecoverSaved(skippedKnown: final skipped)
            when skipped > 0)
          _Footnote(l10n.mfSkippedKnown(skipped)),
        if (state case RecoverSaved(hasCandidates: true))
          _Footnote(l10n.mfVerifyOnDevice),
        if (state case RecoverError(:final errorType)) ...[
          if (_recoveredThisRun > 0)
            _Footnote(l10n.mfKeysKept(_recoveredThisRun)),
          // Only under the error they are about. A copy left by an earlier run
          // is still on the card, but saying so under an unrelated connection
          // failure attaches it to the wrong thing.
          if (errorType == RecoverErrorType.saveFailed) ...[
            if (controller.dictBackupKept)
              _Footnote(l10n.mfBackupKept(flipperDictUserBackupPath)),
            if (controller.dictBackupFailed) _Footnote(l10n.mfBackupLost),
          ],
          // A failed save is the one error whose work is still in memory, so
          // it retries the write alone rather than the whole run.
          _again(
            context,
            errorType == RecoverErrorType.saveFailed
                ? controller.retrySave
                : controller.start,
          ),
        ],
      ],
    );
  }

  /// The one place a fraction becomes text. Null reads as "working" rather than
  /// as 0%, which is a different thing to tell someone.
  static String _percent(double? fraction) =>
      fraction == null ? '…' : '${(fraction * 100).round()}%';

  /// Whichever pieces of progress exist, joined: the run's unit counter when
  /// there is more than one unit, and the current unit's own fraction when the
  /// phase can measure itself. A measurable phase adds to the counter rather
  /// than replacing it - the counter is the only run-level progress there is.
  String _calculatingBar(double? fraction) {
    final parts = [
      if (totalUnits > 1) '$doneUnits / $totalUnits',
      if (fraction != null) _percent(fraction),
    ];
    return parts.isEmpty ? '…' : parts.join(' · ');
  }

  static String _savedTitle(
    int newKeys,
    bool hasCandidates,
    bool hadFailure,
    bool stopped,
  ) {
    final String base;
    // A Stop that landed before anything was attacked has no count to report
    // and no plan to report it against - the step footnote below would read
    // "0 of 0". "No new keys added" would be true and useless: it is the same
    // sentence a finished run that found nothing shows.
    if (stopped && newKeys == 0 && !hasCandidates && !hadFailure) {
      return l10n.mfStoppedNothingYet;
    }
    if (newKeys > 0) {
      // Candidates named alongside the count rather than instead of it. An
      // `else if` here used to drop them from the headline entirely whenever a
      // run also found an ordinary key, which is the common case - and the
      // candidates are the half that still needs the user to do something.
      base = hasCandidates
          ? l10n.mfCandidatesAlso(l10n.mfKeysAdded(newKeys))
          : l10n.mfKeysAdded(newKeys);
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
    RecoverErrorType.saveFailed => l10n.mfSaveFailedAfterRecovery,
  };
}

/// A muted line under the status block: the one place the screen explains what
/// the user has to do next, rather than what just happened.
/// The button that starts a run over.
///
/// One spelling for both the error branch and a stopped run: they offer the
/// same thing and looked different only because the second one was missing.
Widget _again(BuildContext context, VoidCallback onPressed) {
  final colors = context.appColors;
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: FilledButton(
      onPressed: onPressed,
      // Padding and text metrics, to match the app's other buttons. The two
      // colours are deliberately redundant: buildAppTheme already sets
      // colorScheme.primary/onPrimary to accent/onAccent and a FilledButton
      // resolves its defaults to exactly those, so they change nothing on
      // screen. Named anyway so this reads the same as the Stop button beside
      // it, where the colours do differ.
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        context.l10n.commonRetry,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.appColors.textMuted, fontSize: 12),
      ),
    );
  }
}
