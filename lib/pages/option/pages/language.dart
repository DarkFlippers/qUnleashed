import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/localization/controller.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  Widget _tile(
    BuildContext context,
    String title,
    String subtitle,
    bool selected,
  ) {
    final colors = context.appColors;
    return Row(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = QLocaleController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final colors = context.appColors;
        final strings = context.l10n;
        final entries = <Locale?>[null, ...QLocaleController.supported];
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(strings.settingsLanguageTitle),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              GroupedCardList<Locale?>(
                items: entries,
                onTap: (locale) => () => controller.setLocale(locale),
                itemBuilder: (context, locale) => _tile(
                  context,
                  locale == null
                      ? strings.languageSystemDefault
                      : QLocaleController.nameOf(locale),
                  locale == null
                      ? strings.languageSystemDefaultSubtitle
                      : locale.toLanguageTag(),
                  controller.locale == locale,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
