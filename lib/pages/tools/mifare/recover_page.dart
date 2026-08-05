import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/progress_button.dart';
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
            _StatusBlock(state: _controller.state),
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
          addedKeys: controller.addedKeys,
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
      RecoverSource.reader => ('Reader', 'from .mfkey32.log — a reader\'s key'),
      RecoverSource.tag => ('Tag', 'from .nested.log — keys off a card'),
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
  const _CardBlock({
    required this.cuidHex,
    required this.entries,
    required this.addedKeys,
  });

  final String cuidHex;
  final List<RecoverEntry> entries;
  final Set<String> addedKeys;

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
              child: _EntryRow(entry: entry, addedKeys: addedKeys),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.addedKeys});

  final RecoverEntry entry;
  final Set<String> addedKeys;

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
    Color color = colors.textPrimary;
    if (entry.key != null) {
      final known = !addedKeys.contains(entry.key);
      line =
          '${where ?? ''} — ${entry.key}'
          '  [${_kindLabel(entry.kind)}${known ? ', already in dict' : ', new'}]';
    } else if (entry.candidateCount != null) {
      line =
          '${entry.candidateCount} static-encrypted candidate key(s) '
          '→ ${cuidDictFileName(entry.cuid)}';
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
        if (entry.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              entry.note!,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.state});

  final MfKey32State state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (title, showBar, percent) = switch (state) {
      MfKey32WaitingForFlipper() => ('Connecting device…', true, null),
      MfKey32DownloadingRawFile() => ('Downloading nonces…', true, null),
      MfKey32Calculating(:final percent) => ('Recovering keys…', true, percent),
      MfKey32Uploading() => ('Syncing with the device…', true, null),
      MfKey32Saved(:final keys) => (
        keys.isEmpty ? 'No new keys added' : '${keys.length} new key(s) added',
        false,
        null,
      ),
      MfKey32Error(:final errorType) => (_errorText(errorType), false, null),
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
            text: percent == null ? '…' : '',
            color: colors.accent,
            progressColor: colors.accent,
            progress: percent?.clamp(0.0, 1.0),
            indeterminate: percent == null,
            showPercent: percent != null,
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
