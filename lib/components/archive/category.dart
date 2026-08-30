import 'package:flutter/material.dart';
import 'package:qunleashed/theme/colors/category.dart';

import '../../services/localization/l10n.dart';
import 'launch.dart';

export 'launch.dart';

enum ArchiveCategory {
  nfc(
    flipperDirs: ['nfc'],
    extensions: ['nfc'],
    categoryColor: ArchiveCategoryColor.nfc,
    asset: 'assets/ic/fileformat/nfc.svg',
    flipperAppName: 'NFC',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc),
    locationSupport: true,
  ),
  rfid(
    flipperDirs: ['lfrfid'],
    extensions: ['rfid'],
    categoryColor: ArchiveCategoryColor.rfid,
    asset: 'assets/ic/fileformat/rfid.svg',
    flipperAppName: '125 kHz RFID',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc),
    locationSupport: true,
  ),
  ibutton(
    flipperDirs: ['ibutton'],
    extensions: ['ibtn'],
    categoryColor: ArchiveCategoryColor.ibutton,
    asset: 'assets/ic/fileformat/ibutton.svg',
    flipperAppName: 'iButton',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc),
    locationSupport: true,
  ),
  infrared(
    flipperDirs: ['infrared'],
    extensions: ['ir'],
    categoryColor: ArchiveCategoryColor.infrared,
    asset: 'assets/ic/fileformat/ir.svg',
    flipperAppName: 'Infrared',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.app),
    plottable: true,
  ),
  subghz(
    flipperDirs: ['subghz'],
    extensions: ['sub'],
    categoryColor: ArchiveCategoryColor.subghz,
    asset: 'assets/ic/fileformat/sub.svg',
    flipperAppName: 'Sub-GHz',
    recursiveSearch: true,
    launch: LaunchConfig(
      defaultMethod: LaunchMethod.app,
      rules: [
        LaunchRule(whenProtocol: 'RAW', method: LaunchMethod.rpc),
        LaunchRule(whenProtocol: 'BinRAW', method: LaunchMethod.rpc),
      ],
      holdToSend: true,
    ),
    ignoredSubDirs: ['wardriving'],
    locationSupport: true,
    plottable: true,
  ),
  wardriving(
    flipperDirs: ['subghz/wardriving'],
    extensions: ['sub'],
    categoryColor: ArchiveCategoryColor.wardriving,
    asset: 'assets/ic/fileformat/sub.svg',
    subDirs: ['autosaved'],
    flipperAppName: 'Sub-GHz',
    launch: LaunchConfig(defaultMethod: LaunchMethod.rpc, holdToSend: true),
    locationSupport: true,
    plottable: true,
  ),
  badusb(
    flipperDirs: ['badusb', 'badkb'],
    extensions: ['txt'],
    categoryColor: ArchiveCategoryColor.badusb,
    asset: 'assets/ic/fileformat/badusb.svg',
    flipperAppName: 'Bad USB',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.app),
    ignoredFilePrefixes: ['demo_', 'install_qflipper_'],
  ),
  javascript(
    flipperDirs: ['apps/Scripts'],
    extensions: ['js'],
    categoryColor: ArchiveCategoryColor.javascript,
    asset: 'assets/ic/fileformat/js.svg',
    flipperAppName: 'JS Runner',
    recursiveSearch: true,
    launch: LaunchConfig(defaultMethod: LaunchMethod.app),
  );

  const ArchiveCategory({
    required this.flipperDirs,
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

  final List<String> flipperDirs;
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

  String get title => switch (this) {
    ArchiveCategory.nfc => l10n.categoryNfc,
    ArchiveCategory.rfid => l10n.categoryRfid,
    ArchiveCategory.ibutton => l10n.categoryIbutton,
    ArchiveCategory.infrared => l10n.categoryInfrared,
    ArchiveCategory.subghz => l10n.categorySubghz,
    ArchiveCategory.wardriving => l10n.categoryWardriving,
    ArchiveCategory.badusb => l10n.categoryBadusb,
    ArchiveCategory.javascript => l10n.categoryJavascript,
  };

  Color get color => categoryColor.color;

  String get itemNounPlural {
    switch (this) {
      case ArchiveCategory.infrared:
        return l10n.nounRemotes;
      case ArchiveCategory.badusb:
      case ArchiveCategory.javascript:
        return l10n.nounScripts;
      default:
        return l10n.nounKeys;
    }
  }

  bool get emulatable => flipperAppName != null && launch.canLaunch;
  bool get holdToSend => launch.holdToSend;
  String get extension => extensions.first;

  /// Primary directory: where new files are written, and what call sites that
  /// deal with a single directory keep using. Scans walk every [flipperDirs].
  String get flipperDir => flipperDirs.first;
  String get remoteDir => remoteDirOf(flipperDir);
  List<String> get remoteDirs => [for (final d in flipperDirs) remoteDirOf(d)];

  static String remoteDirOf(String flipperDir) => '/ext/$flipperDir';

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
