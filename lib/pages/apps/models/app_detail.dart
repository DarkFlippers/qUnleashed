import 'app_card.dart';

class AppBuildMetadata {
  final String id;
  final String filename;
  final int length;

  const AppBuildMetadata({
    required this.id,
    required this.filename,
    required this.length,
  });

  factory AppBuildMetadata.fromJson(Map<String, dynamic> json) {
    return AppBuildMetadata(
      id: (json['id'] ?? '') as String,
      filename: (json['filename'] ?? '') as String,
      length: (json['length'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppSourceCode {
  final String type;
  final String uri;

  const AppSourceCode({required this.type, required this.uri});

  factory AppSourceCode.fromJson(Map<String, dynamic> json) {
    return AppSourceCode(
      type: (json['type'] ?? '') as String,
      uri: (json['uri'] ?? '') as String,
    );
  }
}

class AppLinks {
  final String? bundleUri;
  final String? manifestUri;
  final AppSourceCode? sourceCode;

  const AppLinks({this.bundleUri, this.manifestUri, this.sourceCode});

  factory AppLinks.fromJson(Map<String, dynamic> json) {
    return AppLinks(
      bundleUri: json['bundle_uri'] as String?,
      manifestUri: json['manifest_uri'] as String?,
      sourceCode: json['source_code'] is Map<String, dynamic>
          ? AppSourceCode.fromJson(json['source_code'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AppDetail {
  final AppCard card;
  final String description;
  final String changelog;
  final AppBuildMetadata? buildMetadata;
  final AppLinks? links;

  const AppDetail({
    required this.card,
    required this.description,
    required this.changelog,
    this.buildMetadata,
    this.links,
  });

  factory AppDetail.fromJson(Map<String, dynamic> json) {
    final card = AppCard.fromJson(json);
    final cv = (json['current_version'] as Map<String, dynamic>?) ?? const {};
    final cb = (cv['current_build'] as Map<String, dynamic>?) ?? const {};
    return AppDetail(
      card: card,
      description: (cv['description'] ?? '') as String,
      changelog: (cv['changelog'] ?? '') as String,
      buildMetadata: cb['metadata'] is Map<String, dynamic>
          ? AppBuildMetadata.fromJson(cb['metadata'] as Map<String, dynamic>)
          : null,
      links: cv['links'] is Map<String, dynamic>
          ? AppLinks.fromJson(cv['links'] as Map<String, dynamic>)
          : null,
    );
  }
}
