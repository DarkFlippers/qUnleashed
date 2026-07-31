import 'file_type.dart';

class UfbtIndexFile {
  const UfbtIndexFile({
    required this.url,
    required this.target,
    required this.type,
    required this.sha256,
  });

  final String url;
  final String target;
  final String type;
  final String? sha256;

  static UfbtIndexFile fromJson(Map<String, dynamic> json) {
    return UfbtIndexFile(
      url: json['url'] as String? ?? '',
      target: json['target'] as String? ?? '',
      type: json['type'] as String? ?? '',
      sha256: json['sha256'] as String?,
    );
  }
}

class UfbtIndexVersion {
  const UfbtIndexVersion({
    required this.version,
    required this.changelog,
    required this.timestamp,
    required this.files,
  });

  final String version;
  final String? changelog;
  final int? timestamp;
  final List<UfbtIndexFile> files;

  static UfbtIndexVersion fromJson(Map<String, dynamic> json) {
    final files = (json['files'] as List?) ?? const [];
    return UfbtIndexVersion(
      version: json['version'] as String? ?? '',
      changelog: json['changelog'] as String?,
      timestamp: json['timestamp'] as int?,
      files: files
          .whereType<Map>()
          .map(
            (file) => UfbtIndexFile.fromJson(Map<String, dynamic>.from(file)),
          )
          .toList(growable: false),
    );
  }

  UfbtIndexFile? findFile(UfbtFileType type, String target) {
    for (final file in files) {
      if (file.type == type.id && file.target == target) return file;
    }
    return null;
  }
}

class UfbtIndexChannel {
  const UfbtIndexChannel({
    required this.id,
    required this.title,
    required this.description,
    required this.versions,
  });

  final String id;
  final String? title;
  final String? description;
  final List<UfbtIndexVersion> versions;

  static UfbtIndexChannel fromJson(Map<String, dynamic> json) {
    final versions = (json['versions'] as List?) ?? const [];
    return UfbtIndexChannel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      description: json['description'] as String?,
      versions: versions
          .whereType<Map>()
          .map(
            (version) =>
                UfbtIndexVersion.fromJson(Map<String, dynamic>.from(version)),
          )
          .toList(growable: false),
    );
  }
}

class UfbtDirectoryIndex {
  const UfbtDirectoryIndex(this.channels);

  final List<UfbtIndexChannel> channels;

  static UfbtDirectoryIndex fromJson(Map<String, dynamic> json) {
    final channels = (json['channels'] as List?) ?? const [];
    return UfbtDirectoryIndex(
      channels
          .whereType<Map>()
          .map(
            (channel) =>
                UfbtIndexChannel.fromJson(Map<String, dynamic>.from(channel)),
          )
          .toList(growable: false),
    );
  }

  UfbtIndexChannel? findChannel(String id) {
    for (final channel in channels) {
      if (channel.id == id) return channel;
    }
    return null;
  }
}
