import 'package:flutter/material.dart';

import '../../../../../theme.dart';

class PaintColorSwatch extends StatelessWidget {
  const PaintColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? accent : Colors.grey.withAlpha(80),
            width: selected ? 2.5 : 1.0,
          ),
        ),
      ),
    );
  }
}

class IconToolButton extends StatelessWidget {
  const IconToolButton({
    super.key,
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final QAppColors colors;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? colors.accent : colors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? colors.onAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
    this.iconTransform,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final QAppColors colors;
  final VoidCallback onTap;
  final Matrix4? iconTransform;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: active ? colors.accent : colors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: iconTransform != null
                ? Transform(
                    transform: iconTransform!,
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 20,
                      color: active ? colors.onAccent : colors.textSecondary,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: active ? colors.onAccent : colors.textSecondary,
                  ),
          ),
        ),
      ),
    );
  }
}

class OpsButton extends StatelessWidget {
  const OpsButton({
    super.key,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.iconTransform,
    this.tooltip,
  });

  final IconData icon;
  final QAppColors colors;
  final VoidCallback onTap;
  final Matrix4? iconTransform;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: iconTransform != null
                ? Transform(
                    transform: iconTransform!,
                    alignment: Alignment.center,
                    child: Icon(icon, size: 20, color: colors.textSecondary),
                  )
                : Icon(icon, size: 20, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class FrameActionButton extends StatelessWidget {
  const FrameActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final QAppColors colors;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? colors.accent : colors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        width: label.isEmpty ? 40 : null,
        decoration: BoxDecoration(
          color: accent ? colors.accent.withAlpha(20) : colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent ? colors.accent.withAlpha(80) : colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ExportButton extends StatelessWidget {
  const ExportButton({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? colors.background : colors.background.withAlpha(80),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.divider),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? colors.textPrimary : colors.textMuted,
        ),
      ),
    );
  }
}

class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.colors,
    required this.onChange,
  });

  final int value;
  final int min;
  final int max;
  final QAppColors colors;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StepButton(
          icon: Icons.remove,
          enabled: value > min,
          colors: colors,
          onTap: () => onChange((value - 1).clamp(min, max)),
        ),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        StepButton(
          icon: Icons.add,
          enabled: value < max,
          colors: colors,
          onTap: () => onChange((value + 1).clamp(min, max)),
        ),
      ],
    );
  }
}

class AnimRow extends StatelessWidget {
  const AnimRow({
    super.key,
    required this.label,
    required this.colors,
    required this.trailing,
    this.unit,
  });

  final String label;
  final String? unit;
  final QAppColors colors;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          if (unit != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                unit!,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ),
          trailing,
        ],
      ),
    );
  }
}
