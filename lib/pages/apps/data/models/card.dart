import 'author.dart';
import 'app_entry.dart';

class AppSdk {
  final String id;
  final String name;
  final String target;
  final String api;
  final bool isLatestRelease;

  const AppSdk({
    required this.id,
    required this.name,
    required this.target,
    required this.api,
    required this.isLatestRelease,
  });

  factory AppSdk.fromStatusJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? '') as String;
    return AppSdk(
      id: version,
      name: version,
      target: (json['target'] ?? '') as String,
      api: (json['api'] ?? '').toString(),
      isLatestRelease: json['channel'] == 'release',
    );
  }

  factory AppSdk.fromJson(Map<String, dynamic> json) {
    return AppSdk(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      target: (json['target'] ?? '') as String,
      api: (json['api'] ?? '').toString(),
      isLatestRelease: (json['is_latest_release'] ?? false) as bool,
    );
  }
}

class AppBuild {
  final String id;
  final AppSdk? sdk;

  const AppBuild({required this.id, this.sdk});

  factory AppBuild.fromJson(Map<String, dynamic> json) {
    return AppBuild(
      id: (json['id'] ?? '') as String,
      sdk: json['sdk'] is Map<String, dynamic>
          ? AppSdk.fromJson(json['sdk'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AppCurrentVersion {
  final String id;
  final String name;
  final String version;
  final String shortDescription;
  final String iconUri;
  final List<String> screenshots;
  final AppBuild? currentBuild;

  const AppCurrentVersion({
    required this.id,
    required this.name,
    required this.version,
    required this.shortDescription,
    required this.iconUri,
    required this.screenshots,
    this.currentBuild,
  });

  factory AppCurrentVersion.fromJson(Map<String, dynamic> json) {
    final shots =
        (json['screenshots'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
    return AppCurrentVersion(
      id: (json['id'] ?? json['_id'] ?? '') as String,
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

class AppStats {
  final int downloads;

  const AppStats({required this.downloads});

  static AppStats? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final downloads = raw['downloads'];
    if (downloads is! num) return null;
    return AppStats(downloads: downloads.toInt());
  }
}

class AppCard {
  final String id;
  final String alias;
  final String categoryId;
  final String author;
  final List<AppAuthor> authors;
  final String? family;
  final AppStats? stats;
  final int createdAt;
  final int updatedAt;
  final AppCurrentVersion? currentVersion;
  final String? installPath;

  /// How many entries the item offers; a list says only this much.
  final int appCount;

  /// The entries themselves, on an item's own card and on a lookup of
  /// installed apps; empty elsewhere.
  final List<CatalogApp> entries;

  /// The entry this card stands for, when it was made for one.
  final String? selectedAppId;

  const AppCard({
    required this.id,
    required this.alias,
    required this.categoryId,
    required this.author,
    this.authors = const [],
    this.family,
    this.stats,
    required this.createdAt,
    required this.updatedAt,
    this.currentVersion,
    this.installPath,
    this.appCount = 1,
    this.entries = const [],
    this.selectedAppId,
  });

  factory AppCard.fromJson(Map<String, dynamic> json) {
    return AppCard(
      id: (json['id'] ?? json['_id'] ?? '') as String,
      alias: (json['alias'] ?? '') as String,
      categoryId: (json['category_id'] ?? '') as String,
      author: (json['author'] ?? '') as String,
      authors: AppAuthor.listFrom(json['authors']),
      family: json['family'] as String?,
      stats: AppStats.fromJson(json['stats']),
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      currentVersion: json['current_version'] is Map<String, dynamic>
          ? AppCurrentVersion.fromJson(
              json['current_version'] as Map<String, dynamic>,
            )
          : null,
      installPath: json['install_path'] as String?,
      appCount: (json['app_count'] as num?)?.toInt() ?? 1,
      entries: CatalogApp.listFrom(json['apps']),
      selectedAppId: json['app'] is String ? json['app'] as String : null,
    );
  }

  /// This card as one of its entries: the alias, version and install path
  /// an install of that entry writes. Texts it does not carry stay those of
  /// this card unless [shortDescription] and [screenshots] say otherwise.
  AppCard forApp(
    CatalogApp entry, {
    String? shortDescription,
    List<String>? screenshots,
  }) {
    final api = entry.buildApi;
    return AppCard(
      id: id,
      alias: entry.appid,
      categoryId: categoryId,
      author: author,
      authors: authors,
      family: family,
      stats: stats,
      createdAt: createdAt,
      updatedAt: updatedAt,
      currentVersion: AppCurrentVersion(
        id: entry.versionId,
        name: entry.name,
        version: entry.version,
        shortDescription: shortDescription ?? this.shortDescription,
        iconUri: entry.iconUri,
        screenshots: screenshots ?? this.screenshots,
        currentBuild: api == null
            ? null
            : AppBuild(
                id: entry.versionId,
                sdk: AppSdk(
                  id: '',
                  name: '',
                  target: '',
                  api: api,
                  isLatestRelease: false,
                ),
              ),
      ),
      installPath: entry.installPath ?? installPath,
      appCount: appCount,
      entries: entries,
      selectedAppId: entry.id,
    );
  }

  /// The entry whose install [versionUid] and [alias] describe: the one
  /// that owns the version, else the first with that app, else none.
  CatalogApp? appInstalledAs(String versionUid, String alias) {
    for (final entry in entries) {
      if (entry.appid == alias && entry.owns(versionUid)) return entry;
    }
    for (final entry in entries) {
      if (entry.appid == alias) return entry;
    }
    return null;
  }

  String get name => currentVersion?.name ?? alias;
  String get shortDescription => currentVersion?.shortDescription ?? '';
  String get iconUri => currentVersion?.iconUri ?? '';
  List<String> get screenshots =>
      currentVersion?.screenshots ?? const <String>[];
}
