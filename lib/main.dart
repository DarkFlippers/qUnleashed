import 'package:flutter/material.dart';

import 'screens/device_list_screen.dart';

void main() {
  runApp(const QunleashedApp());
}

class QunleashedApp extends StatelessWidget {
  const QunleashedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qunleashed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF8200),
          secondary: Color(0xFF589DFF),
          surface: Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFBFBFB),
      ),
      home: const DeviceListScreen(),
    );
  }
}
