import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/progress_button.dart';
import 'mfkey32_models.dart';
import 'nested_controller.dart';

class NestedPage extends StatefulWidget {
  const NestedPage({super.key});

  @override
  State<NestedPage> createState() => _NestedPageState();
}

class _NestedPageState extends State<NestedPage> {
  late final NestedController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NestedController()..addListener(_onChanged);
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
          title: const Text('Nested (Recover MF Keys)'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBlock(state: _controller.state),
            if (_controller.staticCandidateSummary.isNotEmpty ||
                _controller.staticError != null)
              _StaticCandidatesNote(
                summary: _controller.staticCandidateSummary,
                error: _controller.staticError,
              ),
            if (_controller.foundedInformation.keys.isNotEmpty)
              _KeysBlock(controller: _controller),
          ],
        ),
      ),
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
      MfKey32DownloadingRawFile(:final percent) => (
        'Downloading nonces…',
        true,
        percent,
      ),
      MfKey32Calculating(:final percent) => ('Recovering keys…', true, percent),
      MfKey32Uploading() => ('Syncing with the device…', true, null),
      MfKey32Saved(:final keys) => (
        keys.isEmpty ? 'No new keys found' : '${keys.length} new key(s) added',
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
      'No .nested.log found. Collect nested nonces on the device first '
          '(NFC → the sector key you know → collect), then sync and retry.',
    MfKey32ErrorType.readWrite => 'SD card is full or not accessible',
    MfKey32ErrorType.flipperConnection => 'Device not connected',
    MfKey32ErrorType.recoveryFailed =>
      'Key recovery is unavailable on this build — the native component '
          'could not be loaded. Update the app and try again.',
  };
}

class _StaticCandidatesNote extends StatelessWidget {
  const _StaticCandidatesNote({required this.summary, this.error});

  /// (cuid, candidate count) per card processed this run.
  final List<({int cuid, int count})> summary;

  /// Non-null when the static-encrypted step failed (weak keys still saved).
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Static-encrypted (FM11RF08S) candidates',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in summary)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(
                'Card ${entry.cuid.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                '${entry.count == 0 ? ' — no candidates generated' : ' — ${entry.count} candidate keys written to dictionary'}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'A single static-encrypted nonce cannot be resolved to one key '
            'off-device. Read the card (or run a dictionary attack) on your '
            'Flipper to confirm the real keys from these candidates.',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _KeysBlock extends StatelessWidget {
  const _KeysBlock({required this.controller});

  final NestedController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final keys = controller.foundedInformation.keys;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recovered Keys (${keys.length})',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(
                'Sector ${key.sectorName} — Key ${key.keyName} — '
                '${key.key ?? 'Not found'}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
