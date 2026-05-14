import 'package:flutter/material.dart';

import 'pages/devices/page.dart';
import 'theme.dart';

void main() {
  runApp(const QunleashedApp());
}

class QunleashedApp extends StatefulWidget {
  const QunleashedApp({super.key});

  @override
  State<QunleashedApp> createState() => _QunleashedAppState();
}

class _QunleashedAppState extends State<QunleashedApp> {
  final _themeController = QAppThemeController.instance;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) => MaterialApp(
        title: 'Qunleashed',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(_themeController.activeFirmware),
        navigatorKey: _navKey,
        home: const DevicePage(),
      ),
    );
  }
}
