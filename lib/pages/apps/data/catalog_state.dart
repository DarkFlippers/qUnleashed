import 'models/card.dart';
import 'models/manifest.dart';

enum CatalogAppState { install, update, open }

CatalogAppState catalogAppState({
  required AppCard card,
  required AppManifest? manifest,
  required (int major, int minor)? targetSdk,
  bool ignoreSdkMismatch = false,
}) {
  if (manifest == null) return CatalogAppState.install;

  final cv = card.currentVersion;
  if (cv == null) return CatalogAppState.open;

  if (manifest.versionUid.isNotEmpty &&
      cv.id.isNotEmpty &&
      manifest.versionUid != cv.id) {
    return CatalogAppState.update;
  }

  final sdk = ignoreSdkMismatch ? null : _parseSemVer(manifest.sdkApi);
  if (sdk != null && targetSdk != null) {
    final (major, minor) = targetSdk;
    if (sdk.$1 != major || minor < sdk.$2) {
      return CatalogAppState.update;
    }
  }

  return CatalogAppState.open;
}

(int, int)? _parseSemVer(String raw) {
  if (raw.isEmpty) return null;
  final parts = raw.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null) return null;
  final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (major, minor);
}
