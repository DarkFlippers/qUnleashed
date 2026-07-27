import 'manifest.dart';

class InstalledApp {
  final String alias;

  final String path;

  final String folder;

  final int size;

  final String md5;

  final AppManifest? manifest;

  const InstalledApp({
    required this.alias,
    required this.path,
    required this.folder,
    required this.size,
    required this.md5,
    this.manifest,
  });

  bool get hasManifest => manifest != null;

  String get name {
    final full = manifest?.fullName ?? '';
    return full.isNotEmpty ? full : alias;
  }

  String get uid => manifest?.uid ?? '';
}
