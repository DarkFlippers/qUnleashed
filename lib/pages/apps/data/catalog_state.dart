import '../../../components/codec/fap/api_version.dart';
import 'catalog_api.dart' show CatalogFamily;
import 'catalog_context.dart' show aliasFromFapPath;
import 'catalog_server.dart';
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
  return card.appInstalledAs(
    manifest.versionUid,
    aliasFromFapPath(manifest.path),
  );
}

/// The `.fim` an install of [card] from the catalog at [server] writes.
///
/// [buildApi] is the API the file was built for as its source said it, and
/// [devCatalog] what the catalog says it is (AppsCatalogApi.fetchDevCatalog).
AppManifest catalogManifest({
  required AppCard card,
  required AppCurrentVersion version,
  required String path,
  required String server,
  required bool devCatalog,
  String? buildApi,
  String? icon,
}) => AppManifest(
  uid: card.id,
  versionUid: version.id,
  fullName: version.name.isNotEmpty ? version.name : card.name,
  path: path,
  iconBase64: icon,
  sdkApi: buildApi,
  devCatalog: devCatalog,
  appId: card.alias.isNotEmpty ? card.alias : null,
  appVersion: version.version.isNotEmpty ? version.version : null,
  family: switch (CatalogFamily.byServerName(card.family)) {
    CatalogFamily.cli => ManifestFamily.cli,
    CatalogFamily.menuStyles => ManifestFamily.style,
    CatalogFamily.apps ||
    CatalogFamily.animations ||
    null => ManifestFamily.app,
  },
  catalog: CatalogServer.manifestName(server),
);

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
  final versionUid = manifest.versionUid;
  if (versionUid != null &&
      versionUid.isNotEmpty &&
      cv.id.isNotEmpty &&
      versionUid != (installed?.versionId ?? cv.id)) {
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

/// The catalogue's cards for what a device has installed, by the UID of its
/// `.fim`s.
class InstalledCards {
  final Map<String, AppCard> _byUid = {};

  bool get isEmpty => _byUid.isEmpty;

  void replace(Iterable<AppCard> cards) {
    _byUid.clear();
    for (final card in cards) {
      if (card.id.isNotEmpty) _byUid[card.id] = card;
    }
  }

  void clear() => _byUid.clear();

  /// The card [manifest] was installed from, as the app it installed: the
  /// one entry of a multi-app item whose file is on the device.
  AppCard? cardFor(AppManifest? manifest) {
    if (manifest == null) return null;
    final listed = _byUid[manifest.uid];
    if (listed == null) return null;
    final entry = installedApp(listed, manifest);
    return entry == null ? listed : listed.forApp(entry);
  }
}

/// The catalog family [manifest] is looked up in. One that does not say is
/// the official app's, which installs apps only.
CatalogFamily catalogFamilyOf(AppManifest manifest) =>
    switch (manifest.family) {
      ManifestFamily.cli => CatalogFamily.cli,
      ManifestFamily.style => CatalogFamily.menuStyles,
      ManifestFamily.app || null => CatalogFamily.apps,
    };

/// [installed] split by the family each is looked up in, in a stable order.
Map<CatalogFamily, List<AppManifest>> groupByFamily(
  Iterable<AppManifest> installed,
) {
  final out = <CatalogFamily, List<AppManifest>>{};
  for (final m in installed) {
    (out[catalogFamilyOf(m)] ??= []).add(m);
  }
  return {
    for (final family in CatalogFamily.values)
      if (out[family] != null) family: out[family]!,
  };
}

/// [installed] that the catalog at [server] can know by uid - what says it
/// came from there, or does not say where it came from - and, by alias, the
/// catalog each of the others says it came from.
({List<AppManifest> here, Map<String, String> elsewhere}) splitByCatalog(
  Iterable<AppManifest> installed,
  String server,
) {
  final name = CatalogServer.manifestName(server);
  final here = <AppManifest>[];
  final elsewhere = <String, String>{};
  for (final m in installed) {
    if (m.uid.isEmpty) continue;
    final from = m.catalog;
    if (from == null || from == name) {
      here.add(m);
    } else if (m.path.isNotEmpty) {
      elsewhere[aliasFromFapPath(m.path)] = from;
    }
  }
  return (here: here, elsewhere: elsewhere);
}
