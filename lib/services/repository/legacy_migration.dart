// ╔═══════════════════════════════════════════════════════════════════════╗
// ║                                                                       ║
// ║  TODO: УДАЛИТЬ В РЕЛИЗЕ — ВЕСЬ ЭТОТ ФАЙЛ + его вызов в main.dart      ║
// ║  (_bootstrapAmbientServices → 'legacy layout migration').             ║
// ║                                                                       ║
// ║  Одноразовая автоматическая миграция старой раскладки папок           ║
// ║  Documents/qUnleashed на новую:                                       ║
// ║    <root>/<device>            → Devices/<device>                      ║
// ║    <root>/.last_device        → Devices/.last_device                  ║
// ║    <device>/apps/catalog.json → <device>/apps/.catalog.json           ║
// ║    Animations/projects        → Animations/Projects                   ║
// ║    Animations/dolphin         → Animations/Dolphin                    ║
// ║    IRDB/                      → .resources/irlib/                     ║
// ║    irlib/settings.json        → .resources/.irlib.settings.json      ║
// ║    downloads/                 → удаляется совсем                      ║
// ║    updates/ (и Devices/updates/) → удаляется совсем (древний кеш)     ║
// ║                                                                       ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'dart:io' as io;

import 'app.dart';

Future<List<String>> migrateLegacyLayout() async {
  final log = <String>[];
  final sep = io.Platform.pathSeparator;
  final root = await appDocumentsDirectory();
  final devices = await appDevicesDirectory();
  final resources = await appResourcesDirectory();

  const knownRootFolders = {
    kDevicesFolderName,
    kScreenshotsFolderName,
    kRecordingsFolderName,
    kAnimationsFolderName,
    'IRDB',
    'irlib',
    'downloads',
    'updates',
  };

  for (final legacyUpdates in [
    io.Directory('${root.path}${sep}updates'),
    io.Directory('${devices.path}${sep}updates'),
  ]) {
    if (await legacyUpdates.exists()) {
      await legacyUpdates.delete(recursive: true);
      log.add('updates/ удалена');
    }
  }

  Future<void> move(io.FileSystemEntity src, String dstPath) async {
    try {
      await src.rename(dstPath);
    } catch (_) {
      if (src is io.Directory) {
        await _copyTree(src, io.Directory(dstPath));
        await src.delete(recursive: true);
      } else if (src is io.File) {
        await src.copy(dstPath);
        await src.delete();
      }
    }
  }

  final rootDirs = <io.Directory>[
    await for (final entity in root.list(followLinks: false))
      if (entity is io.Directory) entity,
  ];
  for (final entity in rootDirs) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.startsWith('.') || knownRootFolders.contains(name)) continue;
    final target = '${devices.path}$sep$name';
    if (await io.Directory(target).exists()) {
      await _copyTree(entity, io.Directory(target));
      await entity.delete(recursive: true);
    } else {
      await move(entity, target);
    }
    log.add('$name → $kDevicesFolderName/$name');
  }

  final lastDevice = io.File('${root.path}$sep.last_device');
  if (await lastDevice.exists()) {
    await move(lastDevice, '${devices.path}$sep.last_device');
    log.add('.last_device → $kDevicesFolderName/.last_device');
  }

  final deviceDirs = <io.Directory>[
    await for (final entity in devices.list(followLinks: false))
      if (entity is io.Directory) entity,
  ];
  for (final entity in deviceDirs) {
    final catalog = io.File('${entity.path}${sep}apps${sep}catalog.json');
    if (await catalog.exists()) {
      await move(catalog, '${entity.path}${sep}apps$sep$kAppsCatalogFileName');
      log.add('apps/catalog.json → apps/$kAppsCatalogFileName');
    }
  }

  final animations = io.Directory(
    '${root.path}$sep$kAnimationsFolderName',
  );
  if (await animations.exists()) {
    final animationDirs = <io.Directory>[
      await for (final entity in animations.list(followLinks: false))
        if (entity is io.Directory) entity,
    ];
    for (final (from, to) in [
      ('projects', kProjectsFolderName),
      ('dolphin', kDolphinAnimationsFolderName),
    ]) {
      for (final entity in animationDirs) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name != from) continue;
        final tmp = '${animations.path}$sep.$from.migrating';
        await entity.rename(tmp);
        final target = io.Directory('${animations.path}$sep$to');
        if (await target.exists()) {
          await _copyTree(io.Directory(tmp), target);
          await io.Directory(tmp).delete(recursive: true);
        } else {
          await io.Directory(tmp).rename(target.path);
        }
        log.add('$kAnimationsFolderName/$from → $kAnimationsFolderName/$to');
      }
    }
  }

  final irdb = io.Directory('${root.path}${sep}IRDB');
  if (await irdb.exists()) {
    final target = await irLibRepositoryDirectory();
    if (await target.exists()) {
      await irdb.delete(recursive: true);
    } else {
      await move(irdb, target.path);
    }
    log.add('IRDB → $kResourcesFolderName/$kIrLibFolderName');
  }

  final legacyIrSettings = io.File(
    '${root.path}${sep}irlib${sep}settings.json',
  );
  if (await legacyIrSettings.exists()) {
    await move(
      legacyIrSettings,
      '${resources.path}$sep$kIrLibSettingsFileName',
    );
    log.add('irlib/settings.json → $kResourcesFolderName/$kIrLibSettingsFileName');
  }
  final legacyIrDir = io.Directory('${root.path}${sep}irlib');
  if (await legacyIrDir.exists()) {
    try {
      await legacyIrDir.delete(recursive: true);
    } catch (_) {}
  }

  final downloads = io.Directory('${root.path}${sep}downloads');
  if (await downloads.exists()) {
    await downloads.delete(recursive: true);
    log.add('downloads/ удалена');
  }

  return log;
}

Future<void> _copyTree(io.Directory src, io.Directory dst) async {
  if (!await src.exists()) return;
  await dst.create(recursive: true);
  final sep = io.Platform.pathSeparator;
  await for (final entity in src.list(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is io.Directory) {
      await _copyTree(entity, io.Directory('${dst.path}$sep$name'));
    } else if (entity is io.File) {
      final dstFile = io.File('${dst.path}$sep$name');
      if (!await dstFile.exists()) {
        await entity.copy(dstFile.path);
      }
    }
  }
}
