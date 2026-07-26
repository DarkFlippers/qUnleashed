import 'package:flutter/material.dart';

import '../../components/cardlist.dart';
import '../../theme/theme.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  static const Map<QThemeMode, String> _subtitles = {
    QThemeMode.firmware: 'Follow the connected firmware.',
    QThemeMode.system: 'Follow the device light/dark setting.',
    QThemeMode.dark: 'Always use the dark theme.',
    QThemeMode.light: 'Always use the light theme.',
  };

  Widget _tile(BuildContext context, QThemeMode mode, bool selected) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                mode.label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitles[mode]!,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = QAppThemeController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final colors = context.appColors;
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
              GroupedCardList<QThemeMode>(
                items: QThemeMode.values,
                onTap: (mode) => () => controller.setThemeMode(mode),
                itemBuilder: (context, mode) =>
                    _tile(context, mode, controller.themeMode == mode),
              ),
            ],
          ),
        );
      },
    );
  }
}
