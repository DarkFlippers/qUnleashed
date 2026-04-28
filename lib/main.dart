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
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.orange,
          secondary: Colors.orangeAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          foregroundColor: Colors.orange,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const DeviceListScreen(),
    );
  }
}
