class PlanFile {
  const PlanFile({
    required this.devicePath,
    required this.uri,
    required this.size,
    required this.sha256,
  });

  final String devicePath;
  final String uri;
  final int size;
  final String sha256;

  factory PlanFile.fromJson(Map<String, dynamic> json) => PlanFile(
    devicePath: (json['device_path'] ?? '') as String,
    uri: (json['uri'] ?? '') as String,
    size: (json['size'] as num?)?.toInt() ?? 0,
    sha256: ((json['sha256'] ?? '') as String).toLowerCase(),
  );
}

class PlanManifestEntry {
  const PlanManifestEntry({
    required this.name,
    this.minButthurt,
    this.maxButthurt,
    this.minLevel,
    this.maxLevel,
    this.weight,
  });

  final String name;
  final int? minButthurt;
  final int? maxButthurt;
  final int? minLevel;
  final int? maxLevel;
  final int? weight;

  factory PlanManifestEntry.fromJson(Map<String, dynamic> json) =>
      PlanManifestEntry(
        name: (json['name'] ?? '') as String,
        minButthurt: (json['min_butthurt'] as num?)?.toInt(),
        maxButthurt: (json['max_butthurt'] as num?)?.toInt(),
        minLevel: (json['min_level'] as num?)?.toInt(),
        maxLevel: (json['max_level'] as num?)?.toInt(),
        weight: (json['weight'] as num?)?.toInt(),
      );
}

class InstallPlan {
  const InstallPlan({
    required this.files,
    required this.manifestPath,
    required this.entry,
  });

  final List<PlanFile> files;
  final String? manifestPath;
  final PlanManifestEntry? entry;

  factory InstallPlan.fromJson(Map<String, dynamic> json) {
    final files = <PlanFile>[];
    for (final raw in (json['files'] as List?) ?? const []) {
      if (raw is Map<String, dynamic>) files.add(PlanFile.fromJson(raw));
    }
    final merge = json['manifest_merge'];
    final entry = merge is Map<String, dynamic> ? merge['entry'] : null;
    return InstallPlan(
      files: files,
      manifestPath: merge is Map<String, dynamic>
          ? merge['path'] as String?
          : null,
      entry: entry is Map<String, dynamic>
          ? PlanManifestEntry.fromJson(entry)
          : null,
    );
  }
}
