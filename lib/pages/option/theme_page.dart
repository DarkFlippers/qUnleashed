import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  static const Map<QThemeMode, String> _subtitles = {
    QThemeMode.firmware: 'Follow the connected firmware.',
    QThemeMode.system: 'Follow the device light/dark setting.',
    QThemeMode.dark: 'Always use the dark theme.',
    QThemeMode.light: 'Always use the light theme.',
  };

  @override
  Widget build(BuildContext context) {
    final controller = QAppThemeController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final colors = context.appColors;
        final modes = QThemeMode.values;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: const Text('Theme'),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              SettingsGroup(
                children: [
                  for (final mode in modes)
                    _ThemeModeTile(
                      title: mode.label,
                      subtitle: _subtitles[mode]!,
                      selected: controller.themeMode == mode,
                      onTap: () => controller.setThemeMode(mode),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SettingsTileShell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 22,
              color: selected ? colors.accent : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
