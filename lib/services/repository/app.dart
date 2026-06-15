import 'dart:io' as io;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String kAppDocumentsFolderName = 'qUnleashed';
const String kAppsCatalogFileName = 'catalog.json';
const String kScreenshotsFolderName = 'Screenshots';
const String kRecordingsFolderName = 'Recordings';
const String kAnimationsFolderName = 'Animations';
const String kProjectsFolderName = 'projects';

Future<io.File> installedCatalogFile(String deviceName) async {
  final root = await appDocumentsDirectory();
  return io.File(
    pathJoin([
      root.path,
      sanitizePathSegment(deviceName),
      'apps',
      kAppsCatalogFileName,
    ]),
  );
}

String pathJoin(Iterable<String> parts) {
  final sep = io.Platform.pathSeparator;
  final out = <String>[];
  for (final raw in parts) {
    if (raw.isEmpty) continue;
    out.add(raw);
  }
  return out.join(sep);
}

String sanitizePathSegment(String input) {
  return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
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

/// Requests the runtime permission required to write into the shared
/// Documents directory on Android. Returns true if access is granted.
///
/// On Android <= 12 (API <= 32) this maps to WRITE/READ_EXTERNAL_STORAGE.
/// On Android 11+ (API 30+) writing arbitrary files outside the app
/// sandbox requires MANAGE_EXTERNAL_STORAGE, so we fall back to that.
Future<bool> ensureAndroidStoragePermission() async {
  if (!io.Platform.isAndroid) return true;

  if (await Permission.storage.request().isGranted) return true;

  final manage = await Permission.manageExternalStorage.request();
  return manage.isGranted;
}

/// Resolves the shared, user-visible Documents directory on Android
/// (e.g. /storage/emulated/0/Documents) instead of the app-private
/// container that [getApplicationDocumentsDirectory] returns there.
Future<io.Directory?> _androidPublicDocumentsDirectory() async {
  final sep = io.Platform.pathSeparator;

  await ensureAndroidStoragePermission();

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
  final base = await userDocumentsDirectory();
  final dir = io.Directory(pathJoin([base.path, kAppDocumentsFolderName]));
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
/// frame_*.bm). Lives under `Animations/projects`.
Future<io.Directory> appProjectsDirectory() async {
  final root = await appAnimationsDirectory();
  final dir = io.Directory(pathJoin([root.path, kProjectsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

const String kDolphinAnimationsFolderName = 'dolphin';

/// Local mirror of the Flipper's `/ext/dolphin` directory, where each
/// sub-folder is one animation (meta.txt + frame_*.bm) and a manifest.txt
/// describes the set. Lives under `Animations/dolphin`.
Future<io.Directory> appDolphinAnimationsDirectory() async {
  final root = await appAnimationsDirectory();
  final dir = io.Directory(pathJoin([root.path, kDolphinAnimationsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

const String kFapIconsFolderName = '.fap_icons';

Future<io.Directory> fapIconRepoDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kFapIconsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

io.File _fapIconRepoFile(io.Directory dir, String appId) =>
    io.File(pathJoin([dir.path, '${sanitizePathSegment(appId)}.fap.icon']));

Future<bool> hasFapIcon(String appId) async {
  final id = appId.trim();
  if (id.isEmpty) return false;
  try {
    final dir = await fapIconRepoDirectory();
    return _fapIconRepoFile(dir, id).exists();
  } catch (_) {
    return false;
  }
}

Future<Uint8List?> readFapIcon(String appId) async {
  final id = appId.trim();
  if (id.isEmpty) return null;
  try {
    final dir = await fapIconRepoDirectory();
    final file = _fapIconRepoFile(dir, id);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> writeFapIcon(String appId, List<int> bytes) async {
  final id = appId.trim();
  if (id.isEmpty) return;
  try {
    final dir = await fapIconRepoDirectory();
    await _fapIconRepoFile(dir, id).writeAsBytes(bytes, flush: true);
  } catch (_) {}
}

Future<io.Directory> legacyApplicationDocumentsDirectory(
  Iterable<String> parts,
) async {
  final base = await getApplicationDocumentsDirectory();
  return io.Directory(pathJoin([base.path, ...parts]));
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
