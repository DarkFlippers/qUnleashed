/// What an installed app is, as its `.fim` names it. The family codes are
/// short on purpose: every manifest is read over BLE.
///
/// Animations have no `.fim`; the firmware's dolphin manifest lists them.
enum ManifestFamily {
  app('app'),
  cli('cli'),
  style('stl');

  const ManifestFamily(this.code);

  final String code;

  static ManifestFamily? byCode(String? code) {
    for (final family in values) {
      if (family.code == code) return family;
    }
    return null;
  }
}

/// A Flipper Application Installation Manifest, `/ext/apps_manifests/*.fim`.
///
/// The official apps read the same file and keep only the keys they know
/// (UID, Version UID and Path required, everything else optional), so what
/// this app adds goes after theirs and never changes the meaning of one of
/// them. UID and Version UID are the catalog's public ids - Archivarius's
/// ObjectIds, which is what our servers give out as well: the official app
/// sends every UID it finds back to Archivarius, and one that is not an
/// ObjectId fails the whole request (422). An entry's readable name is App ID.
///
/// A key that is absent is null here (ADR 0009), and is left out of the file
/// rather than written empty - except DevCatalog, which is always written.
class AppManifest {
  static const filetype = 'Flipper Application Installation Manifest';

  final String uid;
  final String? versionUid;
  final String? fullName;
  final String path;
  final String? iconBase64;

  /// The API the file was built for, major and minor, as the server reported
  /// it: the firmware loader refuses another major.
  final String? sdkApi;

  /// Built for a development firmware. The official app shows a manifest only
  /// while its own dev-catalog setting matches; our servers say which they
  /// are, and the official catalog is not one.
  final bool devCatalog;

  /// The app's appid in its catalog entry: `proto_pirate_extra`.
  final String? appId;

  /// The version as people read it: `3.0.2`.
  final String? appVersion;

  final ManifestFamily? family;

  /// The catalog it came from: the origin's host, with its port if it has one.
  final String? catalog;

  const AppManifest({
    required this.uid,
    required this.path,
    this.versionUid,
    this.fullName,
    this.iconBase64,
    this.sdkApi,
    this.devCatalog = false,
    this.appId,
    this.appVersion,
    this.family,
    this.catalog,
  });

  String encode() {
    // From a server that does not give out ObjectIds yet, UID is the appid
    // and Version UID <appid>@<version>: they say it already, and every byte
    // is read over BLE. tryParse gives them back.
    final idSaid = appId == uid;
    final versionSaid =
        appVersion != null && versionUid == '${appId ?? uid}@$appVersion';
    final lines = <String>[
      'Filetype: $filetype',
      'Version: 1',
      ?_line('Full Name', fullName),
      ?_line('Icon', iconBase64),
      ?_line('Version Build API', sdkApi),
      'UID: $uid',
      ?_line('Version UID', versionUid),
      'Path: $path',
      'DevCatalog: $devCatalog',
      ?_line('App ID', idSaid ? null : appId),
      ?_line('App Version', versionSaid ? null : appVersion),
      ?_line('Family', family?.code),
      ?_line('Catalog', catalog),
    ];
    return '${lines.join('\n')}\n';
  }

  static String? _line(String key, String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : '$key: $text';
  }

  static AppManifest? tryParse(String body) {
    final map = <String, String>{};
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (value.isNotEmpty) map[key] = value;
    }
    final uid = map['UID'];
    final path = map['Path'];
    if (uid == null || path == null) return null;
    final versionUid = map['Version UID'];
    // What encode leaves out because UID and Version UID already say it.
    final objectId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(uid);
    final appId = map['App ID'] ?? (objectId ? null : uid);
    final at = versionUid?.lastIndexOf('@') ?? -1;
    final appVersion =
        map['App Version'] ??
        (at > 0 && versionUid!.substring(0, at) == appId
            ? versionUid.substring(at + 1)
            : null);
    return AppManifest(
      uid: uid,
      path: path,
      versionUid: versionUid,
      fullName: map['Full Name'],
      iconBase64: map['Icon'],
      sdkApi: map['Version Build API'],
      devCatalog: map['DevCatalog']?.toLowerCase() == 'true',
      appId: appId,
      appVersion: appVersion,
      family: ManifestFamily.byCode(map['Family']),
      catalog: map['Catalog'],
    );
  }
}
