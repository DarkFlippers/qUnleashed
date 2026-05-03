class AppSdk {
  final String id;
  final String name;
  final String target;
  final String api;
  final bool isLatestRelease;
  final int? releasedAt;

  const AppSdk({
    required this.id,
    required this.name,
    required this.target,
    required this.api,
    required this.isLatestRelease,
    this.releasedAt,
  });

  factory AppSdk.fromJson(Map<String, dynamic> json) {
    return AppSdk(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      target: (json['target'] ?? '') as String,
      api: (json['api'] ?? '').toString(),
      isLatestRelease: (json['is_latest_release'] ?? false) as bool,
      releasedAt: (json['released_at'] as num?)?.toInt(),
    );
  }
}

class AppBuild {
  final String id;
  final AppSdk? sdk;
  final String? fapHash;

  const AppBuild({required this.id, this.sdk, this.fapHash});

  factory AppBuild.fromJson(Map<String, dynamic> json) {
    return AppBuild(
      id: (json['id'] ?? '') as String,
      sdk: json['sdk'] is Map<String, dynamic>
          ? AppSdk.fromJson(json['sdk'] as Map<String, dynamic>)
          : null,
      fapHash: json['fap_hash'] as String?,
    );
  }
}

class AppCurrentVersion {
  final String id;
  final String status;
  final String name;
  final String version;
  final String shortDescription;
  final String iconUri;
  final List<String> screenshots;
  final AppBuild? currentBuild;

  const AppCurrentVersion({
    required this.id,
    required this.status,
    required this.name,
    required this.version,
    required this.shortDescription,
    required this.iconUri,
    required this.screenshots,
    this.currentBuild,
  });

  factory AppCurrentVersion.fromJson(Map<String, dynamic> json) {
    final shots = (json['screenshots'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    return AppCurrentVersion(
      id: (json['id'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      version: (json['version'] ?? '') as String,
      shortDescription: (json['short_description'] ?? '') as String,
      iconUri: (json['icon_uri'] ?? '') as String,
      screenshots: shots,
      currentBuild: json['current_build'] is Map<String, dynamic>
          ? AppBuild.fromJson(json['current_build'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AppCard {
  final String id;
  final String alias;
  final String categoryId;
  final String author;
  final int downloads;
  final int createdAt;
  final int updatedAt;
  final AppCurrentVersion? currentVersion;

  const AppCard({
    required this.id,
    required this.alias,
    required this.categoryId,
    required this.author,
    required this.downloads,
    required this.createdAt,
    required this.updatedAt,
    this.currentVersion,
  });

  factory AppCard.fromJson(Map<String, dynamic> json) {
    return AppCard(
      id: (json['id'] ?? '') as String,
      alias: (json['alias'] ?? '') as String,
      categoryId: (json['category_id'] ?? '') as String,
      author: (json['author'] ?? '') as String,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      currentVersion: json['current_version'] is Map<String, dynamic>
          ? AppCurrentVersion.fromJson(
              json['current_version'] as Map<String, dynamic>)
          : null,
    );
  }

  String get name => currentVersion?.name ?? alias;
  String get shortDescription => currentVersion?.shortDescription ?? '';
  String get iconUri => currentVersion?.iconUri ?? '';
  List<String> get screenshots =>
      currentVersion?.screenshots ?? const <String>[];
}
