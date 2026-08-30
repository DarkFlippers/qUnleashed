import 'package:flutter/material.dart';

import '../services/localization/controller.dart';
import '../services/localization/l10n.dart';
import '../theme/theme.dart';
import 'shell.dart';

class QUnleashedApp extends StatelessWidget {
  const QUnleashedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = QAppThemeController.instance;
    final locales = QLocaleController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([controller, locales]),
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          locale: locales.locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: buildAppTheme(controller.brightness, controller.accent),
          themeAnimationDuration: Duration.zero,
          home: const AppShell(),
        );
      },
    );
  }
}
