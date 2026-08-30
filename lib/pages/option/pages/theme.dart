import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  static String _subtitle(L10n s, QThemeMode mode) => switch (mode) {
    QThemeMode.firmware => s.themeModeFirmwareSubtitle,
    QThemeMode.system => s.themeModeSystemSubtitle,
    QThemeMode.dark => s.themeModeDarkSubtitle,
    QThemeMode.light => s.themeModeLightSubtitle,
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
                _subtitle(context.l10n, mode),
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
            title: Text(context.l10n.settingsThemeTitle),
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
