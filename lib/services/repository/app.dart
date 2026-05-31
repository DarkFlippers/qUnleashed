import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String kAppDocumentsFolderName = 'qUnleashed';
const String kAppsCatalogFileName = 'catalog.json';
const String kScreenshotsFolderName = 'Screenshots';
const String kRecordingsFolderName = 'Recordings';
const String kUpdateCacheFolderName = 'updates';

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

Future<io.Directory> updateCacheDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kUpdateCacheFolderName]));
  await dir.create(recursive: true);
  return dir;
}

Future<io.File> updateCacheFile(String name) async {
  final dir = await updateCacheDirectory();
  return io.File(pathJoin([dir.path, '$name.json']));
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
