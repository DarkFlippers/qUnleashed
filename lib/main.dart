import 'package:flutter/material.dart';

import 'pages/devices/device_page.dart';
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

  @override
  void initState() {
    super.initState();
    _themeController.loadConfig();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) => MaterialApp(
        title: 'Qunleashed',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(_themeController.activeFirmware),
        home: const DevicePage(),
      ),
    );
  }
}
