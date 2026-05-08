import 'package:flutter/material.dart';

enum ArchiveCategory {
  subghz(
    title: 'Sub-GHz',
    flipperDir: 'subghz',
    extension: 'sub',
    color: Color(0xFFFFB84A),
    icon: Icons.radio,
  ),
  rfid(
    title: 'RFID 125',
    flipperDir: 'lfrfid',
    extension: 'rfid',
    color: Color(0xFFFF8200),
    icon: Icons.contactless,
  ),
  nfc(
    title: 'NFC',
    flipperDir: 'nfc',
    extension: 'nfc',
    color: Color(0xFF589DFF),
    icon: Icons.nfc,
  ),
  infrared(
    title: 'Infrared',
    flipperDir: 'infrared',
    extension: 'ir',
    color: Color(0xFFE8587E),
    icon: Icons.settings_remote,
  ),
  ibutton(
    title: 'iButton',
    flipperDir: 'ibutton',
    extension: 'ibtn',
    color: Color(0xFF52C24B),
    icon: Icons.key,
  );

  const ArchiveCategory({
    required this.title,
    required this.flipperDir,
    required this.extension,
    required this.color,
    required this.icon,
  });

  final String title;
  final String flipperDir;
  final String extension;
  final Color color;
  final IconData icon;

  String get remoteDir => '/ext/$flipperDir';

  static ArchiveCategory? fromExtension(String ext) {
    final lower = ext.toLowerCase();
    for (final c in values) {
      if (c.extension == lower) return c;
    }
    return null;
  }
}
