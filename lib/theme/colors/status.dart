import 'package:flutter/material.dart';

enum StatusColor {
  error(Color(0xFFE85858)),
  info(Color(0xFF589DFF)),
  warning(Color(0xFFFF9B34)),
  good(Color(0xFF4ADC45));

  const StatusColor(this.color);

  final Color color;
}
