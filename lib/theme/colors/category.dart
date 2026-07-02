import 'package:flutter/material.dart';

enum ArchiveCategoryColor {
  nfc(Color(0xFF34C7A4)),
  rfid(Color(0xFF5856D6)),
  ibutton(Color(0xFF007AFF)),
  infrared(Color(0xFFAF52DE)),
  subghz(Color(0xFFFF9B34)),
  wardriving(Color(0xFF64D2FF)),
  badusb(Color(0xFFFF3B30)),
  javascript(Color.fromARGB(255, 231, 175, 23));

  const ArchiveCategoryColor(this.color);

  final Color color;
}
