import 'package:flutter/material.dart';

import '../../../components/icon.dart';
import '../../../theme/theme.dart';
import 'settings_group.dart';

class SettingsTileShell extends StatelessWidget {
  const SettingsTileShell({super.key, this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: SettingsGroupCorners.of(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: child,
        ),
      ),
    );
  }
}

class _SettingsTileText extends StatelessWidget {
  const _SettingsTileText({
    required this.title,
    required this.subtitle,
    this.muted = false,
  });

  final String title;
  final String subtitle;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted ? colors.textMuted : colors.textPrimary,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 12,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String asset;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SettingsTileShell(
      onTap: onTap,
      child: Row(
        children: [
          QIconBadge(asset: asset, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: _SettingsTileText(title: title, subtitle: subtitle),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: QIcon(
              asset: 'assets/ic/nav/navigate-tool.svg',
              color: colors.textMuted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onChanged != null;
    return SettingsTileShell(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Row(
        children: [
          Expanded(
            child: _SettingsTileText(
              title: title,
              subtitle: subtitle,
              muted: !enabled,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: colors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
