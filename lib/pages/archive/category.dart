import 'package:flutter/material.dart';
import 'package:qunleashed/theme/colors/category.dart';

import 'models/key.dart';

enum LaunchMethod { none, app, rpc }

class LaunchRule {
  const LaunchRule({this.whenProtocol, this.whenMeta, required this.method});

  final String? whenProtocol;
  final ({String key, String value})? whenMeta;
  final LaunchMethod method;
}

class LaunchConfig {
  const LaunchConfig({
    this.defaultMethod = LaunchMethod.none,
    this.rules = const [],
    this.holdToSend = false,
  });

  final LaunchMethod defaultMethod;
  final List<LaunchRule> rules;
  final bool holdToSend;

  bool get canLaunch =>
      defaultMethod != LaunchMethod.none ||
      rules.any((r) => r.method != LaunchMethod.none);

  bool get hasProtocolRules => rules.any((r) => r.whenProtocol != null);

  LaunchMethod resolve({String? protocol, Map<String, String>? meta}) {
    for (final r in rules) {
      if (r.whenProtocol != null &&
          protocol != null &&
          protocol.toLowerCase() == r.whenProtocol!.toLowerCase()) {
        return r.method;
      }
      final whenMeta = r.whenMeta;
      if (whenMeta != null && meta != null && meta[whenMeta.key] == whenMeta.value) {
        return r.method;
      }
    }
    return defaultMethod;
  }
}

enum ArchiveCategory {
  nfc(
    title: 'NFC',
    flipperDir: 'nfc',
    extensions: ['nfc'],
    categoryColor: ArchiveCategoryColor.nfc,
    asset: 'assets/ic/fileformat/nfc.svg',
    flipperAppName: 'NFC',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc),
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
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc),
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
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc),
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
    launch: LaunchConfig(defaultMethod: LaunchMethod.app),
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
    launch: LaunchConfig(
      defaultMethod: LaunchMethod.app,
      rules: [LaunchRule(whenProtocol: 'BinRAW', method: LaunchMethod.rpc)],
      holdToSend: true,
    ),
    ignoredSubDirs: ['wardriving'],
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
    launch: LaunchConfig(
      defaultMethod: LaunchMethod.app,
      rules: [LaunchRule(whenProtocol: 'BinRAW', method: LaunchMethod.rpc)],
      holdToSend: true,
    ),
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
    launch: LaunchConfig(defaultMethod: LaunchMethod.app),
    ignoredFilePrefixes: ['demo_', 'install_qflipper_'],
  ),
  javascript(
    title: 'JavaScript',
    flipperDir: 'apps/Scripts',
    extensions: ['js'],
    categoryColor: ArchiveCategoryColor.javascript,
    asset: 'assets/ic/fileformat/js.svg',
    flipperAppName: 'JS Runner',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.app),
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
    this.launch = const LaunchConfig(),
    this.ignoredSubDirs = const <String>[],
    this.ignoredFilePrefixes = const <String>[],
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
  final LaunchConfig launch;
  final List<String> ignoredSubDirs;
  final List<String> ignoredFilePrefixes;
  final bool locationSupport;
  final bool plottable;

  Color get color => categoryColor.color;
  bool get emulatable => flipperAppName != null && launch.canLaunch;
  bool get holdToSend => launch.holdToSend;
  String get extension => extensions.first;
  String get remoteDir => '/ext/$flipperDir';

  LaunchMethod launchMethodFor(ArchiveKey key) =>
      launch.resolve(protocol: key.protocol, meta: key.meta);

  bool isIgnoredSubDir(String name) {
    if (name == 'assets' || name.startsWith('_') || name.startsWith('.')) {
      return true;
    }
    return ignoredSubDirs.contains(name);
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
    for (final prefix in ignoredFilePrefixes) {
      if (lower.startsWith(prefix)) return true;
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
