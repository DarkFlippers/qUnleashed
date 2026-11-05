import '../../../components/codec/fap/api_version.dart';
import 'models/card.dart';
import 'models/manifest.dart';
import 'models/app_entry.dart';

enum CatalogAppState { install, update, open }

/// The entry [manifest] was installed as, when [card] lists its entries.
///
/// ProtoPirate from OFW and ProtoPirate from our catalogue write the same
/// `proto_pirate.fap`; the `Version UID` in the `.fim` says which one it was,
/// and only that entry's newer version is an update for it.
CatalogApp? installedApp(AppCard card, AppManifest manifest) {
  if (card.entries.isEmpty) return null;
  final base = manifest.path.split('/').last;
  final alias = base.endsWith('.fap')
      ? base.substring(0, base.length - 4)
      : card.alias;
  return card.appInstalledAs(manifest.versionUid, alias);
}

CatalogAppState catalogAppState({
  required AppCard card,
  required AppManifest? manifest,
  required (int major, int minor)? targetSdk,
  bool ignoreSdkMismatch = false,
}) {
  if (manifest == null) return CatalogAppState.install;

  final cv = card.currentVersion;
  if (cv == null) return CatalogAppState.open;

  final installed = installedApp(card, manifest);
  // A card made for another entry than the one on the device installs over
  // it rather than updating it.
  if (installed != null &&
      card.selectedAppId != null &&
      installed.id != card.selectedAppId) {
    return CatalogAppState.install;
  }
  final latest = installed?.versionId ?? cv.id;
  if (manifest.versionUid.isNotEmpty &&
      latest.isNotEmpty &&
      manifest.versionUid != latest) {
    return CatalogAppState.update;
  }

  // Only another major needs a rebuild; the firmware loader ignores the
  // minor, and so does the catalog when it picks the SDK to serve.
  final sdk = ignoreSdkMismatch ? null : parseApi(manifest.sdkApi);
  if (sdk != null && targetSdk != null && sdk.$1 != targetSdk.$1) {
    return CatalogAppState.update;
  }

  return CatalogAppState.open;
}
