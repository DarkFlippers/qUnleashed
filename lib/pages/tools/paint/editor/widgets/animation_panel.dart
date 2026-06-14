import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../theme/theme.dart';
import '../controller.dart';
import 'editor_widgets.dart';

class AnimationPanel extends StatelessWidget {
  const AnimationPanel({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final n = ctrl.frames.length;
    final passiveN = ctrl.effectivePassiveCount;
    final activeN = n - passiveN;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'ANIMATION',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => ctrl.setCompressBm(!ctrl.compressBm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: ctrl.compressBm
                          ? colors.accent.withAlpha(30)
                          : colors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: ctrl.compressBm ? colors.accent : colors.divider,
                      ),
                    ),
                    child: Text(
                      ctrl.compressBm ? 'Compress ✓' : 'Compress',
                      style: TextStyle(
                        color: ctrl.compressBm
                            ? colors.accent
                            : colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Frame rate',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colors.accent,
                      thumbColor: colors.accent,
                      inactiveTrackColor: colors.divider,
                      overlayColor: colors.accent.withAlpha(30),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: ctrl.frameRate.toDouble().clamp(1, 10),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: (v) => ctrl.setFrameRate(v.round()),
                    ),
                  ),
                ),
                Text(
                  '${ctrl.frameRate} fps',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            Row(
              children: [
                Text(
                  'Passive  $passiveN',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  'Active  $activeN',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.accent,
                thumbColor: colors.accent,
                inactiveTrackColor: colors.divider.withAlpha(180),
                overlayColor: colors.accent.withAlpha(30),
                trackHeight: 3,
              ),
              child: Slider(
                value: passiveN.toDouble().clamp(0, math.max(n, 1).toDouble()),
                min: 0,
                max: math.max(n, 1).toDouble(),
                divisions: math.max(n, 1),
                onChanged: n > 1
                    ? (v) => ctrl.setPassiveFrameCount(v.round())
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            AnimRow(
              label: 'Duration',
              unit: 's',
              colors: colors,
              trailing: NumberStepper(
                value: ctrl.duration,
                min: 1,
                max: 99999,
                colors: colors,
                onChange: ctrl.setDuration,
              ),
            ),
            Opacity(
              opacity: activeN > 0 ? 1.0 : 0.38,
              child: IgnorePointer(
                ignoring: activeN == 0,
                child: Column(
                  children: [
                    AnimRow(
                      label: 'Active cycles',
                      colors: colors,
                      trailing: NumberStepper(
                        value: ctrl.activeCycles,
                        min: 1,
                        max: 99,
                        colors: colors,
                        onChange: ctrl.setActiveCycles,
                      ),
                    ),
                    AnimRow(
                      label: 'Active cooldown',
                      unit: 's',
                      colors: colors,
                      trailing: NumberStepper(
                        value: ctrl.activeCooldown,
                        min: 0,
                        max: 3600,
                        colors: colors,
                        onChange: ctrl.setActiveCooldown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: ctrl.triggerActive,
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors.accent.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors.accent.withAlpha(80),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 15,
                              color: colors.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Trigger Active',
                              style: TextStyle(
                                color: colors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
