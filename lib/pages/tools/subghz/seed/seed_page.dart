import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../../components/dialogs/confirm.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import 'seed_controller.dart';
import 'seed_models.dart';

/// Recovers the seed of a FAAC SLH, Genius, BFT or Erreka remote from a capture
/// the Flipper-side app collected, and writes the result back as a
/// transmittable `.sub`.
class SeedPage extends StatefulWidget {
  const SeedPage({super.key, required this.client});

  /// The Flipper this run belongs to. Required rather than defaulted: the route
  /// builder is handed a context with a DeviceScope above it, so a default
  /// would only hide which device a recovery ran against. ADR 0002.
  final FlipperClient client;

  @override
  State<SeedPage> createState() => _SeedPageState();
}

class _SeedPageState extends State<SeedPage> {
  late final SeedController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SeedController(client: widget.client)
      ..addListener(_onChanged);
    _controller.refresh();
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

  Future<bool> _confirmStop() => QConfirmDialog.show(
    context,
    title: context.l10n.seedStopTitle,
    message: context.l10n.seedStopMessage,
    confirmLabel: context.l10n.seedStopConfirm,
    cancelLabel: context.l10n.seedStopCancel,
  );

  bool get _searching => _controller.stage == SeedStage.searching;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmStop() && mounted) {
          _controller.stop();
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          title: Text(context.l10n.seedTitle),
          actions: [
            IconButton(
              tooltip: context.l10n.seedRefresh,
              onPressed: _searching ? null : _controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_controller.capture != null) ...[
              _CaptureCard(controller: _controller),
              const SizedBox(height: 12),
              _ActionBlock(controller: _controller, confirmStop: _confirmStop),
              const SizedBox(height: 12),
              if (_controller.result != null)
                _ResultCard(controller: _controller),
              const SizedBox(height: 20),
            ],
            _CaptureList(controller: _controller),
          ],
        ),
      ),
    );
  }
}

/// What the capture holds, before anything is attacked.
class _CaptureCard extends StatelessWidget {
  const _CaptureCard({required this.controller});

  final SeedController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final capture = controller.capture!;
    final frequency = capture.frequencyHz;
    return _Card(
      children: [
        _Row(
          label: context.l10n.seedManufacturer,
          value: capture.manufacturer.label,
        ),
        // Fix, seed and counter are the three figures the result is read for;
        // the fix is known before the search and is shown from the start so a
        // user can check they opened the right capture.
        _Row(label: context.l10n.seedFix, value: _hex(capture.fix, 8)),
        _Row(
          label: context.l10n.seedHops(capture.hops.length),
          value: capture.hops.map((h) => _hex(h, 8)).join('  '),
          wrap: true,
        ),
        if (frequency != null)
          _Row(
            label: context.l10n.seedFrequency,
            value: '${(frequency / 1000000).toStringAsFixed(2)} MHz',
          ),
        if (controller.captureWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.l10n.seedSkippedLines(controller.captureWarnings.length),
              style: TextStyle(fontSize: 12, color: colors.info),
            ),
          ),
      ],
    );
  }
}

/// Start, progress and stop.
class _ActionBlock extends StatelessWidget {
  const _ActionBlock({required this.controller, required this.confirmStop});

  final SeedController controller;
  final Future<bool> Function() confirmStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (controller.stage == SeedStage.searching) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.seedSearching,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: controller.progress,
            color: colors.accent,
            backgroundColor: colors.divider,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: controller.cancelled
                ? null
                : () async {
                    if (await confirmStop()) controller.stop();
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.danger,
              disabledForegroundColor: colors.textMuted,
              side: BorderSide(
                color: controller.cancelled ? colors.divider : colors.danger,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              context.l10n.seedStop,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    return FilledButton(
      onPressed: controller.capture!.isSolvable ? controller.search : null,
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        context.l10n.seedStart,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// What came back, and what can be done with it.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.controller});

  final SeedController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final result = controller.result!;
    final capture = controller.capture!;

    final (headline, tint) = switch (result.outcome) {
      SeedOutcome.found => (l10n.seedFound, colors.success),
      SeedOutcome.unverified => (l10n.seedUnverified, colors.info),
      SeedOutcome.nothingMatched => (l10n.seedNothingMatched, colors.textMuted),
      SeedOutcome.stopped => (l10n.seedStopped, colors.textMuted),
      SeedOutcome.engineBusy => (l10n.seedEngineBusy, colors.info),
      SeedOutcome.engineSelfTestFailed => (
        l10n.seedEngineBroken,
        colors.danger,
      ),
      SeedOutcome.engineFault => (l10n.seedEngineFault, colors.danger),
    };

    final seed = result.seed;
    final counter = result.counter;
    final hopsUsed = result.hopsUsed;

    return _Card(
      children: [
        Text(
          headline,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tint,
          ),
        ),
        const SizedBox(height: 8),
        if (seed != null) ...[
          _Row(label: l10n.seedFix, value: _hex(capture.fix, 8)),
          _Row(label: l10n.seedSeed, value: _hex(seed, 8)),
          if (counter != null)
            _Row(
              label: l10n.seedCounter,
              value: _hex(counter, capture.manufacturer.counterDigits),
            ),
        ],
        // A no-match is the result most likely to be misread as a verdict on
        // the remote, so it is the one that gets an explanation rather than a
        // line of status.
        if (result.outcome == SeedOutcome.nothingMatched)
          _Hint(l10n.seedNothingMatchedHint),
        if (result.outcome == SeedOutcome.unverified)
          _Hint(l10n.seedUnverifiedHint),
        if (seed != null && hopsUsed != null && hopsUsed < seedHopsConfident)
          _Hint(l10n.seedLowConfidence(hopsUsed)),
        if (result.outcome == SeedOutcome.found && capture.frequencyHz == null)
          _Hint(l10n.seedSaveNoFrequency),
        if (controller.canSave) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: controller.savedTo == null ? controller.save : null,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(l10n.seedSave),
          ),
        ],
        if (controller.savedTo != null)
          _Hint(l10n.seedSaved(controller.savedTo!)),
      ],
    );
  }
}

/// The captures the device is holding.
class _CaptureList extends StatelessWidget {
  const _CaptureList({required this.controller});

  final SeedController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    if (controller.files.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.seedNoCaptures,
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.seedNoCapturesHint,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.seedCapturesTitle,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        for (final file in controller.files)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              file.name,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
            onTap: controller.stage == SeedStage.searching
                ? null
                : () => controller.open(file),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.wrap = false});

  final String label;
  final String value;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              softWrap: wrap,
              overflow: wrap ? TextOverflow.clip : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: colors.textMuted),
      ),
    );
  }
}

String _hex(int value, int digits) =>
    value.toRadixString(16).toUpperCase().padLeft(digits, '0');
