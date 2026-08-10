import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'shell.dart';

class QUnleashedApp extends StatelessWidget {
  const QUnleashedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = QAppThemeController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'qUnleashed',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(controller.brightness, controller.accent),
          themeAnimationDuration: Duration.zero,
          home: const AppShell(),
        );
      },
    );
  }
}
