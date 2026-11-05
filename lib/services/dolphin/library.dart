import 'dart:io' as io;

import '../../components/path.dart';
import '../storage/paths.dart';

const String kDolphinRoot = '/ext/dolphin';
const String kDolphinManifestPath = '$kDolphinRoot/manifest.txt';

Future<io.File?> dolphinLibraryFile(String devicePath) async {
  if (!devicePath.startsWith('$kDolphinRoot/')) return null;
  final root = await appDolphinAnimationsDirectory();
  final path = resolveArchivePath(
    root.path,
    devicePath.substring(kDolphinRoot.length + 1),
  );
  return path == null ? null : io.File(path);
}

Future<void> saveToDolphinLibrary(String devicePath, List<int> bytes) async {
  final file = await dolphinLibraryFile(devicePath);
  if (file == null) return;
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}
