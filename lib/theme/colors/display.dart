import 'package:flutter/material.dart';

import '../theme.dart';

@immutable
class DisplayColors {
  const DisplayColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;

  static const DisplayColors light = DisplayColors(
    background: Color(0xFFFF8200),
    foreground: Color(0xFF000000),
    border: Color(0xFF000000),
  );

  static const DisplayColors dark = DisplayColors(
    background: Color(0xFFDFDFDF),
    foreground: Color(0xFF000000),
    border: Color(0xFF231F20),
  );

  static DisplayColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static DisplayColors forColors(QAppColors colors) =>
      colors.isDark ? dark : light;

  static DisplayColors get current =>
      of(QAppThemeController.instance.brightness);
}
