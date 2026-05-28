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
    launchOnRpc: true,
    locationSupport: true,
  ),
  rfid(
    title: 'RFID 125',
    flipperDir: 'lfrfid',
    extensions: ['rfid'],
    color: Color(0xFF5856D6),
    asset: 'assets/flipper_svg/archive/ic_fileformat_rf.svg',
    flipperAppName: '125 kHz RFID',
    recursiveSearch: true,
    launchOnRpc: true,
    locationSupport: true,
  ),
  ibutton(
    title: 'iButton',
    flipperDir: 'ibutton',
    extensions: ['ibtn'],
    color: Color(0xFF007AFF),
    asset: 'assets/flipper_svg/archive/ic_fileformat_ibutton.svg',
    flipperAppName: 'iButton',
    recursiveSearch: true,
    launchOnRpc: true,
    locationSupport: true,
  ),
  infrared(
    title: 'Infrared',
    flipperDir: 'infrared',
    extensions: ['ir'],
    color: Color(0xFFAF52DE),
    asset: 'assets/flipper_svg/archive/ic_fileformat_ir.svg',
    flipperAppName: 'Infrared',
    recursiveSearch: true,
    launchOnApp: true,
  ),
  subghz(
    title: 'Sub-GHz',
    flipperDir: 'subghz',
    extensions: ['bin', 'sub'],
    color: Color(0xFFFF9B34),
    asset: 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
    flipperAppName: 'Sub-GHz',
    recursiveSearch: true,
    launchOnApp: true,
    locationSupport: true,
  ),
  wardriving(
    title: 'Wardriving',
    flipperDir: 'subghz/wardriving',
    extensions: ['bin', 'sub'],
    color: Color(0xFF64D2FF),
    asset: 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
    subDirs: ['autosaved'],
    flipperAppName: 'Sub-GHz',
    launchOnApp: true,
    locationSupport: true,
  ),
  badusb(
    title: 'Bad USB',
    flipperDir: 'badusb',
    extensions: ['txt'],
    color: Color(0xFFFF3B30),
    asset: 'assets/flipper_svg/archive/ic_fileformat_badusb.svg',
    flipperAppName: 'Bad USB',
    recursiveSearch: true,
    launchOnApp: true,
  ),
  javascript(
    title: 'JavaScript',
    flipperDir: 'apps/Scripts',
    extensions: ['js'],
    color: Color(0xFFFFCC00),
    asset: 'assets/flipper_svg/archive/ic_file.svg',
    flipperAppName: 'JS Runner',
    recursiveSearch: true,
    launchOnApp: true,
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
    this.launchOnApp = false,
    this.launchOnRpc = false,
    this.locationSupport = false,
  });

  final String title;
  final String flipperDir;
  final List<String> extensions;
  final Color color;
  final String asset;
  final List<String> subDirs;
  final String? flipperAppName;
  final bool recursiveSearch;
  final bool launchOnApp;
  final bool launchOnRpc;
  final bool locationSupport;

  bool get emulatable =>
      flipperAppName != null && (launchOnApp || launchOnRpc);
  String get extension => extensions.first;
  String get remoteDir => '/ext/$flipperDir';

  static bool isIgnoredSubDir(String name) {
    if (name == 'wardriving' || name == 'assets') return true;
    if (name.startsWith('_') || name.startsWith('.')) return true;
    return false;
  }

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

  static ArchiveCategory? fromExtension(String ext) {
    final lower = ext.toLowerCase();
    for (final c in values) {
      if (c.extensions.contains(lower)) return c;
    }
    return null;
  }
}
