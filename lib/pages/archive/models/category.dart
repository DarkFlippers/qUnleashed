import 'package:flutter/material.dart';

enum ArchiveCategory {
  nfc(
    title: 'NFC',
    flipperDir: 'nfc',
    extensions: ['nfc'],
    color: Color(0xFF34C7A4),
    asset: 'assets/flipper_svg/archive/ic_fileformat_nfc.svg',
    flipperAppName: 'NFC',
    recursiveSearch: true,
  ),
  rfid(
    title: 'RFID 125',
    flipperDir: 'lfrfid',
    extensions: ['rfid'],
    color: Color(0xFF5856D6),
    asset: 'assets/flipper_svg/archive/ic_fileformat_rf.svg',
    flipperAppName: '125 kHz RFID',
    recursiveSearch: true,
  ),
  ibutton(
    title: 'iButton',
    flipperDir: 'ibutton',
    extensions: ['ibtn'],
    color: Color(0xFF007AFF),
    asset: 'assets/flipper_svg/archive/ic_fileformat_ibutton.svg',
    flipperAppName: 'iButton',
    recursiveSearch: true,
  ),
  infrared(
    title: 'Infrared',
    flipperDir: 'infrared',
    extensions: ['ir'],
    color: Color(0xFFAF52DE),
    asset: 'assets/flipper_svg/archive/ic_fileformat_ir.svg',
    flipperAppName: 'Infrared',
    recursiveSearch: true,
  ),
  subghz(
    title: 'Sub-GHz',
    flipperDir: 'subghz',
    extensions: ['bin', 'sub'],
    color: Color(0xFFFF9B34),
    asset: 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
    flipperAppName: 'Sub-GHz',
    recursiveSearch: true,
  ),
  wardriving(
    title: 'Wardriving',
    flipperDir: 'subghz/wardriving',
    extensions: ['bin', 'sub'],
    color: Color(0xFFFFB84A),
    asset: 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
    subDirs: ['autosaved'],
  ),
  badusb(
    title: 'Bad USB',
    flipperDir: 'badusb',
    extensions: ['txt'],
    color: Color(0xFFFF3B30),
    asset: 'assets/flipper_svg/archive/ic_fileformat_badusb.svg',
    flipperAppName: 'Bad USB',
    recursiveSearch: true,
  );

  const ArchiveCategory({
    required this.title,
    required this.flipperDir,
    required this.extensions,
    required this.color,
    required this.asset,
    this.subDirs = const <String>[],
    this.flipperAppName,
    this.recursiveSearch = false,
  });

  final String title;
  final String flipperDir;
  final List<String> extensions;
  final Color color;
  final String asset;
  final List<String> subDirs;
  final String? flipperAppName;
  final bool recursiveSearch;

  bool get emulatable => flipperAppName != null;
  bool get needsButtonPress =>
      this == ArchiveCategory.subghz || this == ArchiveCategory.infrared;

  String get extension => extensions.first;

  String? matchExtension(String fileName) {
    final lower = fileName.toLowerCase();
    for (final ext in extensions) {
      if (lower.endsWith('.$ext')) return ext;
    }
    return null;
  }

  bool isIgnoredFile(String fileName) {
    final lower = fileName.toLowerCase();
    if (this == ArchiveCategory.badusb) {
      if (lower.startsWith('demo_')) return true;
      if (lower.startsWith('install_qflipper_')) return true;
    }
    return false;
  }

  String get remoteDir => '/ext/$flipperDir';

  static ArchiveCategory? fromExtension(String ext) {
    final lower = ext.toLowerCase();
    for (final c in values) {
      if (c.extensions.contains(lower)) return c;
    }
    return null;
  }
}
