import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';

import '../../components/path.dart';
import 'permissions.dart';

const String kAppDocumentsFolderName = 'qUnleashed';
const String kDevicesFolderName = 'Devices';
const String kAppsCatalogFileName = '.catalog.json';
const String kScreenshotsFolderName = 'Screenshots';
const String kRecordingsFolderName = 'Recordings';
const String kAnimationsFolderName = 'Animations';
const String kProjectsFolderName = 'Projects';
const String kResourcesFolderName = '.resources';
const String kIrLibFolderName = 'irlib';
const String kAtpFolderName = 'all-the-plugins';
const String kAtpIndexFileName = 'index.txt';

/// Name of the last connected device, written by the archive to
/// `Devices/.last_device`. Lets offline screens resolve their local folder.
Future<String?> lastDeviceName() async {
  try {
    final root = await appDevicesDirectory();
    final file = io.File(pathJoin([root.path, '.last_device']));
    if (!await file.exists()) return null;
    final raw = (await file.readAsString()).trim();
    return raw.isEmpty ? null : raw;
  } catch (_) {
    return null;
  }
}

Future<io.File> installedCatalogFile(String deviceName) async {
  final root = await appDevicesDirectory();
  return io.File(
    pathJoin([
      root.path,
      sanitizePathSegment(deviceName),
      'apps',
      kAppsCatalogFileName,
    ]),
  );
}

/// Local mirror of the device's `/ext/apps`, where the manager backs up every
/// `.fap`. Lives at `Devices/<name>/apps`.
Future<io.Directory> appsBackupDirectory(String deviceName) async {
  final root = await appDevicesDirectory();
  final dir = io.Directory(
    pathJoin([root.path, sanitizePathSegment(deviceName), 'apps']),
  );
  await dir.create(recursive: true);
  return dir;
}

String? normalizeFlipperDeviceName(String? raw) {
  if (raw == null) return null;
  var name = raw.trim();
  final prefix = RegExp(r'^flipper[\s_-]+', caseSensitive: false);
  name = name.replaceFirst(prefix, '').trim();
  return name.isEmpty ? null : name;
}

Future<io.Directory> userDocumentsDirectory() async {
  final sep = io.Platform.pathSeparator;

  if (io.Platform.isWindows) {
    final userProfile = io.Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return io.Directory('$userProfile${sep}Documents');
    }
  }

  if (io.Platform.isMacOS) {
    final home = _macosRealHomeDirectory();
    if (home != null && home.isNotEmpty) {
      return io.Directory('$home${sep}Documents');
    }
  }

  if (io.Platform.isLinux) {
    final home = io.Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return io.Directory('$home${sep}Documents');
    }
  }

  if (io.Platform.isAndroid) {
    final documents = await _androidPublicDocumentsDirectory();
    if (documents != null) return documents;
  }

  // iOS: getApplicationDocumentsDirectory() returns the app sandbox
  // Documents folder, which is the correct (and only writable) location.
  return getApplicationDocumentsDirectory();
}

/// Resolves the shared, user-visible Documents directory on Android
/// (e.g. /storage/emulated/0/Documents) instead of the app-private
/// container that [getApplicationDocumentsDirectory] returns there.
Future<io.Directory?> _androidPublicDocumentsDirectory() async {
  final sep = io.Platform.pathSeparator;

  // getExternalStorageDirectory() -> /storage/emulated/0/Android/data/<pkg>/files
  // The external storage root is everything before the "/Android/" segment.
  final external = await getExternalStorageDirectory();
  if (external != null) {
    final marker = '${sep}Android$sep';
    final index = external.path.indexOf(marker);
    if (index > 0) {
      final root = external.path.substring(0, index);
      return io.Directory('$root${sep}Documents');
    }
  }

  // Fallback to the conventional primary external storage path.
  return io.Directory('${sep}storage${sep}emulated${sep}0${sep}Documents');
}

Future<io.Directory> appDocumentsDirectory() async {
  await ensureAndroidStoragePermission();
  final base = await userDocumentsDirectory();
  final dir = io.Directory(pathJoin([base.path, kAppDocumentsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> appDevicesDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kDevicesFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> appResourcesDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kResourcesFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> irLibRepositoryDirectory() async {
  final root = await appResourcesDirectory();
  return io.Directory(pathJoin([root.path, kIrLibFolderName]));
}

Future<io.Directory> atpRepositoryDirectory() async {
  final root = await appResourcesDirectory();
  final dir = io.Directory(pathJoin([root.path, kAtpFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.File> atpIndexFile() async {
  final root = await atpRepositoryDirectory();
  return io.File(pathJoin([root.path, kAtpIndexFileName]));
}

Future<io.Directory> shareCacheDirectory() async {
  final base = await getTemporaryDirectory();
  final dir = io.Directory(pathJoin([base.path, 'qunleashed_share']));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> appScreenshotsDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kScreenshotsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> appRecordingsDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kRecordingsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> appAnimationsDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kAnimationsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

/// Saved Pixel Draw projects (each a Dolphin animation folder: meta.txt +
/// frame_*.bm). Lives under `Animations/Projects`.
Future<io.Directory> appProjectsDirectory() async {
  final root = await appAnimationsDirectory();
  final dir = io.Directory(pathJoin([root.path, kProjectsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

const String kDolphinAnimationsFolderName = 'Dolphin';

/// Local mirror of the Flipper's `/ext/dolphin` directory, where each
/// sub-folder is one animation (meta.txt + frame_*.bm) and a manifest.txt
/// describes the set. Lives under `Animations/Dolphin`.
Future<io.Directory> appDolphinAnimationsDirectory() async {
  final root = await appAnimationsDirectory();
  final dir = io.Directory(pathJoin([root.path, kDolphinAnimationsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.Directory> legacyApplicationDocumentsDirectory(
  Iterable<String> parts,
) async {
  final base = await getApplicationDocumentsDirectory();
  return io.Directory(pathJoin([base.path, ...parts]));
}

Future<int> directorySize(io.Directory dir) async {
  if (!await dir.exists()) return 0;
  var total = 0;
  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! io.File) continue;
      try {
        total += await entity.length();
      } catch (_) {}
    }
  } catch (_) {}
  return total;
}

Future<void> clearDirectory(io.Directory dir) async {
  if (!await dir.exists()) return;
  await for (final entity in dir.list(followLinks: false)) {
    try {
      await entity.delete(recursive: true);
    } catch (_) {}
  }
}

const String kIrLibSettingsFileName = '.irlib.settings.json';

Future<io.File> irLibSettingsFile() async {
  final root = await appResourcesDirectory();
  return io.File(pathJoin([root.path, kIrLibSettingsFileName]));
}

String? _macosRealHomeDirectory() {
  final home = io.Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;
  final sandboxMarker =
      '${io.Platform.pathSeparator}Library'
      '${io.Platform.pathSeparator}Containers'
      '${io.Platform.pathSeparator}';
  final markerIndex = home.indexOf(sandboxMarker);
  if (markerIndex > 0) {
    return home.substring(0, markerIndex);
  }
  return home;
}
