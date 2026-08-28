import '../../../components/codec/fap/api_version.dart';
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

  final sdk = ignoreSdkMismatch ? null : parseApi(manifest.sdkApi);
  if (sdk != null && targetSdk != null) {
    final (major, minor) = targetSdk;
    if (sdk.$1 != major || minor < sdk.$2) {
      return CatalogAppState.update;
    }
  }

  return CatalogAppState.open;
}
