import '../../../../../services/localization/l10n.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../theme/theme.dart';
import '../controller.dart';
import 'editor_widgets.dart';

/// Dolphin animation settings. Every value is a stepper on its own line; the
/// lines pair up into two columns as soon as the pane is wide enough.
class AnimationPanel extends StatelessWidget {
  const AnimationPanel({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final n = ctrl.frames.length;
    final passiveN = ctrl.effectivePassiveCount;
    final activeN = n - passiveN;
    final hasActive = activeN > 0;

    final rows = <Widget>[
      AnimRow(
        label: context.l10n.paintFrameRate,
        colors: colors,
        trailing: NumberStepper(
          value: ctrl.frameRate,
          min: 1,
          max: 10,
          colors: colors,
          onChange: ctrl.setFrameRate,
          text: context.l10n.paintFps(ctrl.frameRate),
        ),
      ),
      AnimRow(
        label:
            '${context.l10n.paintPassiveCount(passiveN)}'
            ' · ${context.l10n.paintActiveCount(activeN)}',
        colors: colors,
        trailing: NumberStepper(
          value: passiveN,
          min: 0,
          max: math.max(n, 1),
          colors: colors,
          onChange: ctrl.setPassiveFrameCount,
        ),
      ),
      AnimRow(
        label: context.l10n.paintDuration,
        colors: colors,
        trailing: NumberStepper(
          value: ctrl.duration,
          min: 1,
          max: 99999,
          colors: colors,
          onChange: ctrl.setDuration,
          width: 56,
        ),
      ),
      Opacity(
        opacity: hasActive ? 1 : 0.38,
        child: IgnorePointer(
          ignoring: !hasActive,
          child: AnimRow(
            label: context.l10n.paintActiveCycles,
            colors: colors,
            trailing: NumberStepper(
              value: ctrl.activeCycles,
              min: 1,
              max: 99,
              colors: colors,
              onChange: ctrl.setActiveCycles,
            ),
          ),
        ),
      ),
      Opacity(
        opacity: hasActive ? 1 : 0.38,
        child: IgnorePointer(
          ignoring: !hasActive,
          child: AnimRow(
            label: context.l10n.paintActiveCooldown,
            colors: colors,
            trailing: NumberStepper(
              value: ctrl.activeCooldown,
              min: 0,
              max: 3600,
              colors: colors,
              onChange: ctrl.setActiveCooldown,
              width: 56,
            ),
          ),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (_, c) {
                if (c.maxWidth < 420) {
                  return Column(children: rows);
                }
                final half = (rows.length / 2).ceil();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: rows.sublist(0, half))),
                    const SizedBox(width: 18),
                    Expanded(child: Column(children: rows.sublist(half))),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Toggle(
                  label: ctrl.compressBm
                      ? context.l10n.paintCompressOn
                      : context.l10n.paintCompress,
                  active: ctrl.compressBm,
                  colors: colors,
                  onTap: () => ctrl.setCompressBm(!ctrl.compressBm),
                ),
                const Spacer(),
                _Toggle(
                  label: context.l10n.paintTriggerActive,
                  icon: Icons.touch_app_outlined,
                  active: false,
                  enabled: hasActive,
                  colors: colors,
                  onTap: ctrl.triggerActive,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.active,
    required this.colors,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final bool enabled;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? colors.textMuted.withAlpha(110)
        : active
        ? colors.accent
        : colors.textSecondary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? colors.accent.withAlpha(26) : colors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
