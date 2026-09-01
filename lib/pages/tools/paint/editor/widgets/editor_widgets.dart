import 'package:flutter/material.dart';

import '../../../../../theme/theme.dart';

/// The two ink colours side by side; the one being drawn with is outlined.
class InkSwatches extends StatelessWidget {
  const InkSwatches({
    super.key,
    required this.foreground,
    required this.background,
    required this.drawFg,
    required this.colors,
    required this.onPick,
    this.size = 26,
  });

  final Color foreground;
  final Color background;
  final bool drawFg;
  final double size;
  final QAppColors colors;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Swatch(
          color: foreground,
          selected: drawFg,
          size: size,
          colors: colors,
          onTap: () => onPick(true),
        ),
        const SizedBox(width: 5),
        _Swatch(
          color: background,
          selected: !drawFg,
          size: size,
          colors: colors,
          onTap: () => onPick(false),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.size,
    required this.colors,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final double size;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

/// Borderless 30×30 icon button for the dock's thin top line.
class MiniToolButton extends StatelessWidget {
  const MiniToolButton({
    super.key,
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
    this.tooltip,
    this.enabled = true,
    this.iconTransform,
  });

  final IconData icon;
  final bool active;
  final bool enabled;
  final Matrix4? iconTransform;
  final QAppColors colors;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Transform(
            transform: iconTransform ?? Matrix4.identity(),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: !enabled
                  ? colors.textMuted.withAlpha(110)
                  : active
                  ? colors.onAccent
                  : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawing tool button; fills the height it is given.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
    this.iconTransform,
    this.tooltip,
    this.background,
  });

  final IconData icon;
  final bool active;
  final QAppColors colors;
  final VoidCallback onTap;
  final Matrix4? iconTransform;
  final String? tooltip;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      this.icon,
      size: 20,
      color: active ? colors.onAccent : colors.textSecondary,
    );
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: active ? colors.accent : (background ?? colors.card),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: iconTransform != null
              ? Transform(
                  transform: iconTransform!,
                  alignment: Alignment.center,
                  child: icon,
                )
              : icon,
        ),
      ),
    );
  }
}

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: colors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class StepButton extends StatelessWidget {
  const StepButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          icon,
          size: 15,
          color: enabled ? colors.textPrimary : colors.textMuted.withAlpha(90),
        ),
      ),
    );
  }
}

/// Compact "− value +" control used by the animation settings.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.colors,
    required this.onChange,
    this.step = 1,
    this.width = 46,
    this.text,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final double width;
  final String? text;
  final QAppColors colors;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final enabled = min < max;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StepButton(
            icon: Icons.remove,
            enabled: enabled && value > min,
            colors: colors,
            onTap: () => onChange((value - step).clamp(min, max)),
          ),
          SizedBox(
            width: width,
            child: Text(
              text ?? '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: enabled ? colors.textPrimary : colors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          StepButton(
            icon: Icons.add,
            enabled: enabled && value < max,
            colors: colors,
            onTap: () => onChange((value + step).clamp(min, max)),
          ),
        ],
      ),
    );
  }
}

/// One "label … control" line of the animation settings.
class AnimRow extends StatelessWidget {
  const AnimRow({
    super.key,
    required this.label,
    required this.colors,
    required this.trailing,
  });

  final String label;
  final QAppColors colors;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
