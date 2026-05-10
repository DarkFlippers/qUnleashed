class AppManifest {
  final String uid;
  final String versionUid;
  final String fullName;
  final String path;
  final String iconBase64;
  final String sdkApi;
  final bool devCatalog;

  const AppManifest({
    required this.uid,
    required this.versionUid,
    required this.fullName,
    required this.path,
    required this.iconBase64,
    required this.sdkApi,
    required this.devCatalog,
  });

  String encode() {
    final lines = <String>[
      'Filetype: Flipper Application Installation Manifest',
      'Version: 1',
      'Full Name: $fullName',
      'Icon: $iconBase64',
      'Version Build API: $sdkApi',
      'UID: $uid',
      'Version UID: $versionUid',
      'Path: $path',
      'DevCatalog: ${devCatalog ? 'true' : 'false'}',
    ];
    return '${lines.join('\n')}\n';
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
      map[key] = value;
    }
    final uid = map['UID'];
    final path = map['Path'];
    if (uid == null || path == null) return null;
    return AppManifest(
      uid: uid,
      versionUid: map['Version UID'] ?? '',
      fullName: map['Full Name'] ?? '',
      path: path,
      iconBase64: map['Icon'] ?? '',
      sdkApi: map['Version Build API'] ?? '',
      devCatalog: (map['DevCatalog'] ?? 'false').toLowerCase() == 'true',
    );
  }
}
