import '../../../components/codec/fap/api_version.dart';
import 'catalog_api.dart' show CatalogFamily;
import 'catalog_context.dart'
    show aliasFromFapPath, kCliPluginsRoot, kMenuStylesRoot;
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
  final base = manifest.path.split('/').last;
  final alias = base.endsWith('.fap')
      ? base.substring(0, base.length - 4)
      : card.alias;
  return card.appInstalledAs(manifest.versionUid ?? '', alias);
}

/// Whether [versionUid] is [version] when no entry of the card says which app
/// it was installed as: its public id, or, from a `.fim` written before the
/// server gave out public ids, `<id>@<version>` with the same version.
bool isCurrentVersion(String versionUid, AppCurrentVersion version) {
  if (versionUid == version.id) return true;
  final at = versionUid.lastIndexOf('@');
  return at > 0 &&
      version.version.isNotEmpty &&
      versionUid.substring(at + 1) == version.version;
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
      !(installed?.isVersion(versionUid) ?? isCurrentVersion(versionUid, cv))) {
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

/// The catalogue's cards for what a device has installed, found from its
/// `.fim`s.
class InstalledCards {
  final Map<String, AppCard> _byUid = {};

  /// The same cards by every appid they offer: a `.fim` written before the
  /// server gave out public ids names its entry by the appid, not by the
  /// ObjectId the card now carries.
  final Map<String, AppCard> _byAppid = {};

  bool get isEmpty => _byUid.isEmpty && _byAppid.isEmpty;

  void replace(Iterable<AppCard> cards) {
    clear();
    for (final card in cards) {
      if (card.id.isNotEmpty) _byUid[card.id] = card;
      if (card.alias.isNotEmpty) _byAppid[card.alias] = card;
      for (final entry in card.entries) {
        _byAppid[entry.appid] = card;
        _byAppid[entry.id] = card;
      }
    }
  }

  void clear() {
    _byUid.clear();
    _byAppid.clear();
  }

  /// The card [manifest] was installed from, as the app it installed: the
  /// one entry of a multi-app item whose file is on the device.
  AppCard? cardFor(AppManifest? manifest) {
    if (manifest == null) return null;
    final listed = _listedFor(manifest);
    if (listed == null) return null;
    final entry = installedApp(listed, manifest);
    return entry == null ? listed : listed.forApp(entry);
  }

  AppCard? _listedFor(AppManifest manifest) {
    final byUid = manifest.uid.isEmpty ? null : _byUid[manifest.uid];
    if (byUid != null) return byUid;
    final alias = manifest.path.isEmpty ? '' : aliasFromFapPath(manifest.path);
    return _byAppid[manifest.uid] ?? _byAppid[alias];
  }
}

/// The catalog family [manifest] is looked up in: what its `.fim` says, or,
/// in one written before it said, where its file is.
CatalogFamily catalogFamilyOf(AppManifest manifest) =>
    switch (manifest.family) {
      ManifestFamily.app => CatalogFamily.apps,
      ManifestFamily.cli => CatalogFamily.cli,
      ManifestFamily.style => CatalogFamily.menuStyles,
      null when manifest.path.startsWith('$kCliPluginsRoot/') =>
        CatalogFamily.cli,
      null when manifest.path.startsWith('$kMenuStylesRoot/') =>
        CatalogFamily.menuStyles,
      null => CatalogFamily.apps,
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
