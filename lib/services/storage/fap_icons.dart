import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import '../../components/path.dart';
import 'paths.dart';

const String kFapIconsFolderName = '.fap_icons';

Future<io.Directory> fapIconRepoDirectory() async {
  final root = await appDocumentsDirectory();
  final dir = io.Directory(pathJoin([root.path, kFapIconsFolderName]));
  await dir.create(recursive: true);
  return dir;
}

io.File _fapIconRepoFile(io.Directory dir, String appId) =>
    io.File(pathJoin([dir.path, '${sanitizePathSegment(appId)}.fap.icon']));

final ValueNotifier<int> _fapIconRevision = ValueNotifier<int>(0);
ValueListenable<int> get fapIconRevision => _fapIconRevision;

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
    _fapIconRevision.value++;
  } catch (_) {}
}
