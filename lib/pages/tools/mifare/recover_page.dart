import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../components/progress_button.dart';
import 'existed_keys_storage.dart';
import 'mfkey32_models.dart';
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

  Future<bool> _confirmAbort() async {
    final abort = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.dialogBackground,
        title: Text(
          'Stop Key Recovery?',
          style: TextStyle(color: context.appColors.dialogText),
        ),
        content: Text(
          'You can restart it later',
          style: TextStyle(color: context.appColors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return abort ?? false;
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
          title: const Text('Recover MIFARE Keys'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBlock(
              state: _controller.state,
              totalUnits: _controller.totalUnits,
              doneUnits: _controller.doneUnits,
              hasCandidates: _controller.entries.any(
                (e) => e.candidateCount != null,
              ),
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

  final bySource = <RecoverSource, Map<int, List<RecoverEntry>>>{};
  for (final entry in entries) {
    bySource
        .putIfAbsent(entry.source, () => <int, List<RecoverEntry>>{})
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
        'Reader',
        'Key a reader used on your emulated card · .mfkey32.log',
      ),
      RecoverSource.tag => (
        'Card',
        'Keys recovered from a card you scanned · .nested.log',
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

  final String cuidHex;
  final List<RecoverEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Card $cuidHex',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
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
    RecoverKind.weakNested => 'weak nested',
    RecoverKind.staticNonce => 'static nonce',
    RecoverKind.staticEncrypted => 'static-encrypted',
    RecoverKind.hardnested => 'hardnested',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final where = (entry.sectorName != null && entry.keyName != null)
        ? 'Sector ${entry.sectorName} · Key ${entry.keyName}'
        : null;

    final String line;
    String? explainer;
    Color color = colors.textPrimary;
    if (entry.key != null) {
      // isNew is decided at recovery time, so this tag is already correct while
      // the run is still in progress - not only in the final summary.
      final tag = entry.isNew == false ? 'already in dict' : 'new';
      line =
          '${where ?? ''} — ${entry.key}  [${_kindLabel(entry.kind)}, $tag]';
    } else if (entry.candidateCount != null) {
      line =
          '${entry.candidateCount} candidate keys → ${cuidDictFileName(entry.cuid)}';
      explainer =
          'Possible keys for this card — the correct ones are among them.';
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
    required this.hasCandidates,
  });

  final MfKey32State state;
  final int totalUnits;
  final int doneUnits;
  final bool hasCandidates;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Each recovery unit is atomic (a native call with no sub-progress) and
    // units vary wildly in duration (a hardnested attack dwarfs an mfkey32 one),
    // so a percentage freezes between units and misleads. Instead the bar always
    // animates (liveness) and, when there is more than one unit, shows how many
    // are done - honest progress that never looks stuck.
    final (title, showBar, barText) = switch (state) {
      MfKey32WaitingForFlipper() => ('Connecting device…', true, '…'),
      MfKey32DownloadingRawFile() => ('Downloading nonces…', true, '…'),
      MfKey32Calculating() => (
        'Recovering keys…',
        true,
        totalUnits > 1 ? '$doneUnits / $totalUnits' : '…',
      ),
      MfKey32Uploading() => ('Syncing with the device…', true, '…'),
      MfKey32Saved(:final keys) => (
        keys.isNotEmpty
            ? '${keys.length} new key(s) added'
            : hasCandidates
            ? 'Candidate keys saved'
            : 'No new keys added',
        false,
        '',
      ),
      MfKey32Error(:final errorType) => (_errorText(errorType), false, ''),
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
        if (showBar)
          ProgressButton(
            text: barText,
            color: colors.accent,
            progressColor: colors.accent,
            indeterminate: true,
            showPercent: false,
            height: 46,
          ),
      ],
    );
  }

  static String _errorText(MfKey32ErrorType type) => switch (type) {
    MfKey32ErrorType.notFoundFile =>
      'No .mfkey32.log or .nested.log found. Collect nonces on the device '
          '(emulate a card against a reader, or read a card with a known key), '
          'then sync and retry.',
    MfKey32ErrorType.readWrite => 'SD card is full or not accessible',
    MfKey32ErrorType.flipperConnection => 'Device not connected',
    MfKey32ErrorType.recoveryFailed =>
      'Key recovery is unavailable on this build — a native component could '
          'not be loaded. Update the app and try again.',
  };
}
