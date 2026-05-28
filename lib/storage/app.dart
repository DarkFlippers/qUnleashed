import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';

const String kAppDocumentsFolderName = 'qUnleashed';
const String kAppsCatalogFileName = 'catalog.json';

Future<io.File> installedCatalogFile(String deviceName) async {
  final root = await appDocumentsDirectory();
  return io.File(pathJoin([
    root.path,
    sanitizePathSegment(deviceName),
    'apps',
    kAppsCatalogFileName,
  ]));
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

  return getApplicationDocumentsDirectory();
}

Future<io.Directory> appDocumentsDirectory() async {
  final base = await userDocumentsDirectory();
  final dir = io.Directory(pathJoin([base.path, kAppDocumentsFolderName]));
  await dir.create(recursive: true);
  return dir;
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
