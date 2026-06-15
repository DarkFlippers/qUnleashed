import 'package:flipperlib/flipperlib.dart' show RecoveryStep;
import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../../../widgets/page_card.dart';
import '../../device_scope.dart';
import '../../firmware/directory.dart';
import '../../recovery/recovery_scope.dart';
import '../../recovery/recovery_state.dart';

class RecoveryCard extends StatelessWidget {
  const RecoveryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final recovery = RecoveryScope.of(context);
    final state = recovery.state;

    return FlipperPageCard(
      title: 'Device Recovery',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        child: switch (state) {
          RecoveryEnteringDfu() => _Busy(
            label: 'Entering DFU mode…',
            colors: colors,
          ),
          RecoveryFetching(:final progress) => _Busy(
            label: 'Downloading firmware… ${(progress * 100).round()}%',
            progress: progress,
            colors: colors,
          ),
          RecoveryRunning(:final step, :final percent) => _Busy(
            label: _stepLabel(step, percent),
            progress: _stepProgress(step, percent),
            colors: colors,
          ),
          RecoveryDoneState() => _Result(
            icon: Icons.check_circle,
            color: colors.success,
            message: 'Firmware restored. The device is restarting.',
            actionLabel: 'Done',
            onAction: recovery.reset,
            colors: colors,
          ),
          RecoveryErrorState(:final message) => _Result(
            icon: Icons.error_outline,
            color: colors.danger,
            message: 'Recovery failed: $message',
            actionLabel: 'Try again',
            onAction: () => _startRepair(context),
            secondaryLabel: 'Dismiss',
            onSecondary: recovery.reset,
            colors: colors,
          ),
          RecoveryIdle() => _Prompt(
            onRepair: () => _startRepair(context),
            colors: colors,
          ),
        },
      ),
    );
  }

  static void _startRepair(BuildContext context) {
    final recovery = RecoveryScope.of(context);
    recovery.repair(parser: OfwParser.instance, channelId: 'release');
  }

  static String _stepLabel(RecoveryStep step, double percent) {
    switch (step) {
      case RecoveryStep.settingBootMode:
        return 'Preparing device…';
      case RecoveryStep.flashingRadio:
        return 'Flashing radio stack… ${percent.round()}%';
      case RecoveryStep.flashingFirmware:
        return 'Flashing firmware… ${percent.round()}%';
      case RecoveryStep.correctingOptionBytes:
        return 'Finalizing…';
      case RecoveryStep.restarting:
        return 'Restarting…';
    }
  }

  static double? _stepProgress(RecoveryStep step, double percent) {
    switch (step) {
      case RecoveryStep.flashingRadio:
      case RecoveryStep.flashingFirmware:
        return (percent / 100).clamp(0.0, 1.0);
      case RecoveryStep.settingBootMode:
      case RecoveryStep.correctingOptionBytes:
      case RecoveryStep.restarting:
        return null;
    }
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.onRepair, required this.colors});

  final VoidCallback onRepair;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final device = DeviceScope.of(context);
    final inDfu = device.dfuPresent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inDfu
              ? 'A device is in DFU (bootloader) mode. Reinstall the firmware to '
                    'restore it.'
              : 'Reinstall the firmware over USB to restore an unresponsive '
                    'device.',
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        const SizedBox(height: 12),
        _AccentButton(label: 'Repair Device', onTap: onRepair, colors: colors),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label, required this.colors, this.progress});

  final String label;
  final double? progress;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: colors.textPrimary)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: colors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Do not disconnect the device.',
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.icon,
    required this.color,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.colors,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AccentButton(
                label: actionLabel,
                onTap: onAction,
                colors: colors,
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _AccentButton(
                  label: secondaryLabel!,
                  onTap: onSecondary!,
                  colors: colors,
                  outlined: true,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({
    required this.label,
    required this.onTap,
    required this.colors,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onTap;
  final QAppColors colors;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: outlined ? Colors.transparent : colors.accent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: outlined
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.divider),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: outlined ? colors.textPrimary : colors.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}
