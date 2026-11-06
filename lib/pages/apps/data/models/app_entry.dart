/// One external application in a v1 item's `apps` list. Every entry shares
/// the version's description, changelog and screenshots.
class CatalogApp {
  const CatalogApp({
    required this.id,
    required this.appid,
    required this.main,
    required this.isDefault,
    required this.name,
    required this.iconUri,
    required this.version,
    required this.versionId,
    required this.installPath,
    required this.status,
    this.buildApi,
    this.buildSize,
    this.bundleUri,
  });

  final String id;
  final String appid;
  final bool main;
  final bool isDefault;
  final String name;
  final String iconUri;
  final String version;
  final String versionId;
  final String? installPath;
  final String status;
  final String? buildApi;
  final int? buildSize;
  final String? bundleUri;

  /// Whether [versionUid], a `.fim`'s `Version UID`, names a version of this
  /// app: its public id, or the `<id>@<version>` a `.fim` written before the
  /// server gave out public ids holds.
  bool owns(String versionUid) =>
      versionUid == versionId || versionUid.startsWith('$id@');

  /// Whether [versionUid] is this app's current version, in either shape.
  bool isVersion(String versionUid) =>
      versionUid == versionId || versionUid == '$id@$version';

  static CatalogApp? tryFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _text(raw['id']),
        appid = _text(raw['appid']),
        versionId = _text(raw['version_id']);
    if (id == null || appid == null || versionId == null) return null;
    final build = raw['build'];
    return CatalogApp(
      id: id,
      appid: appid,
      versionId: versionId,
      main: raw['main'] == true,
      isDefault: raw['default'] == true,
      name: _text(raw['name']) ?? appid,
      iconUri: _text(raw['icon_uri']) ?? '',
      version: _text(raw['version']) ?? '',
      installPath: _text(raw['install_path']),
      status: _text(raw['status']) ?? 'never',
      bundleUri: _text(raw['bundle_uri']),
      buildApi: build is Map ? _text(build['api']) : null,
      buildSize: build is Map && build['size'] is num
          ? (build['size'] as num).toInt()
          : null,
    );
  }

  static List<CatalogApp> listFrom(Object? raw) => raw is List
      ? List.unmodifiable(raw.map(tryFrom).whereType<CatalogApp>())
      : const [];

  static String? _text(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
}
