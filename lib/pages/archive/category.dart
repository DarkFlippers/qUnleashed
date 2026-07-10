import 'package:flutter/material.dart';
import 'package:qunleashed/theme/colors/category.dart';

enum ArchiveCategory {
  nfc(
    title: 'NFC',
    flipperDir: 'nfc',
    extensions: ['nfc'],
    categoryColor: ArchiveCategoryColor.nfc,
    asset: 'assets/ic/fileformat/nfc.svg',
    flipperAppName: 'NFC',
    recursiveSearch: true,
    launchOnRpc: true,
    locationSupport: true,
  ),
  rfid(
    title: 'RFID 125',
    flipperDir: 'lfrfid',
    extensions: ['rfid'],
    categoryColor: ArchiveCategoryColor.rfid,
    asset: 'assets/ic/fileformat/rfid.svg',
    flipperAppName: '125 kHz RFID',
    recursiveSearch: true,
    launchOnRpc: true,
    locationSupport: true,
  ),
  ibutton(
    title: 'iButton',
    flipperDir: 'ibutton',
    extensions: ['ibtn'],
    categoryColor: ArchiveCategoryColor.ibutton,
    asset: 'assets/ic/fileformat/ibutton.svg',
    flipperAppName: 'iButton',
    recursiveSearch: true,
    launchOnRpc: true,
    locationSupport: true,
  ),
  infrared(
    title: 'Infrared',
    flipperDir: 'infrared',
    extensions: ['ir'],
    categoryColor: ArchiveCategoryColor.infrared,
    asset: 'assets/ic/fileformat/ir.svg',
    flipperAppName: 'Infrared',
    recursiveSearch: true,
    launchOnApp: true,
    plottable: true,
  ),
  subghz(
    title: 'Sub-GHz',
    flipperDir: 'subghz',
    extensions: ['sub'],
    categoryColor: ArchiveCategoryColor.subghz,
    asset: 'assets/ic/fileformat/sub.svg',
    flipperAppName: 'Sub-GHz',
    recursiveSearch: true,
    launchOnApp: true,
    locationSupport: true,
    plottable: true,
  ),
  wardriving(
    title: 'Wardriving',
    flipperDir: 'subghz/wardriving',
    extensions: ['sub'],
    categoryColor: ArchiveCategoryColor.wardriving,
    asset: 'assets/ic/fileformat/sub.svg',
    subDirs: ['autosaved'],
    flipperAppName: 'Sub-GHz',
    launchOnApp: true,
    locationSupport: true,
    plottable: true,
  ),
  badusb(
    title: 'Bad USB',
    flipperDir: 'badusb',
    extensions: ['txt'],
    categoryColor: ArchiveCategoryColor.badusb,
    asset: 'assets/ic/fileformat/badusb.svg',
    flipperAppName: 'Bad USB',
    recursiveSearch: true,
    launchOnApp: true,
  ),
  javascript(
    title: 'JavaScript',
    flipperDir: 'apps/Scripts',
    extensions: ['js'],
    categoryColor: ArchiveCategoryColor.javascript,
    asset: 'assets/ic/fileformat/js.svg',
    flipperAppName: 'JS Runner',
    recursiveSearch: true,
    launchOnApp: true,
  );

  const ArchiveCategory({
    required this.title,
    required this.flipperDir,
    required this.extensions,
    required this.categoryColor,
    required this.asset,
    this.subDirs = const <String>[],
    this.flipperAppName,
    this.recursiveSearch = false,
    this.launchOnApp = false,
    this.launchOnRpc = false,
    this.locationSupport = false,
    this.plottable = false,
  });

  final String title;
  final String flipperDir;
  final List<String> extensions;
  final ArchiveCategoryColor categoryColor;
  final String asset;
  final List<String> subDirs;
  final String? flipperAppName;
  final bool recursiveSearch;
  final bool launchOnApp;
  final bool launchOnRpc;
  final bool locationSupport;
  final bool plottable;

  Color get color => categoryColor.color;
  bool get emulatable => flipperAppName != null && (launchOnApp || launchOnRpc);
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
