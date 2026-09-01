part of '../page.dart';

const double kMapControl = 38;

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.colors,
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
    this.active = false,
  });

  final QAppColors colors;
  final IconData icon;
  final VoidCallback? onTap;
  final String? label;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final text = label;
    final background = active ? colors.accent : colors.card;
    final tint = active
        ? colors.onAccent
        : (onTap == null ? colors.textMuted : colors.accent);

    Widget control = Material(
      color: background,
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(kMapControl / 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kMapControl,
          width: text == null ? kMapControl : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: tint),
                if (text != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      color: active ? colors.onAccent : colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final message = tooltip;
    if (message != null) control = Tooltip(message: message, child: control);
    return control;
  }
}
