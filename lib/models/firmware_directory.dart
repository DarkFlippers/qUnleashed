import 'dart:convert';
import 'dart:io';

// =============================================================================
// Enums
// =============================================================================

enum FirmwareChannel {
  release,
  releaseCandidate,
  development;

  String get id => switch (this) {
        FirmwareChannel.release => 'release',
        FirmwareChannel.releaseCandidate => 'release-candidate',
        FirmwareChannel.development => 'development',
      };

  String get displayName => switch (this) {
        FirmwareChannel.release => 'Stable Release',
        FirmwareChannel.releaseCandidate => 'Release Candidate',
        FirmwareChannel.development => 'Development',
      };
}

enum UnleashedVariant {
  /// Only essential apps, same set as OFW
  base,

  /// Large list of pre-installed apps
  extraPacks,

  /// No apps, firmware only
  compact;

  String get displayName => switch (this) {
        UnleashedVariant.base => 'Base',
        UnleashedVariant.extraPacks => 'Extra Packs',
        UnleashedVariant.compact => 'Compact',
      };
}

// =============================================================================
// Data models
// =============================================================================

class FirmwareFile {
  const FirmwareFile({
    required this.url,
    required this.target,
    required this.type,
    required this.sha256,
  });

  final String url;
  final String target;
  final String type;
  final String sha256;

  factory FirmwareFile.fromJson(Map<String, dynamic> json) => FirmwareFile(
        url: json['url'] as String,
        target: json['target'] as String,
        type: json['type'] as String,
        sha256: json['sha256'] as String,
      );

  String get fileName => url.split('/').last;
}

class FirmwareVersion {
  const FirmwareVersion({
    required this.version,
    required this.changelog,
    required this.timestamp,
    required this.files,
  });

  final String version;
  final String changelog;
  final int timestamp;
  final List<FirmwareFile> files;

  DateTime get releaseDate => DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  FirmwareFile? fileOfType(String type, {String? target}) {
    for (final f in files) {
      if (f.type != type) continue;
      if (target != null && f.target != target) continue;
      return f;
    }
    return null;
  }

  FirmwareFile? updatePackageFor(String target) =>
      fileOfType('update_tgz', target: target);

  FirmwareFile? get updatePackage => fileOfType('update_tgz');

  factory FirmwareVersion.fromJson(Map<String, dynamic> json) => FirmwareVersion(
        version: json['version'] as String,
        changelog: (json['changelog'] as String?) ?? '',
        timestamp: (json['timestamp'] as num).toInt(),
        files: ((json['files'] as List<dynamic>?) ?? [])
            .map((e) => FirmwareFile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FirmwareDirectoryChannel {
  const FirmwareDirectoryChannel({
    required this.id,
    required this.title,
    required this.description,
    required this.versions,
  });

  final String id;
  final String title;
  final String description;
  final List<FirmwareVersion> versions;

  FirmwareVersion? get latest => versions.isNotEmpty ? versions.first : null;

  factory FirmwareDirectoryChannel.fromJson(Map<String, dynamic> json) =>
      FirmwareDirectoryChannel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        versions: ((json['versions'] as List<dynamic>?) ?? [])
            .map((e) => FirmwareVersion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FirmwareDirectory {
  const FirmwareDirectory({required this.channels});

  final List<FirmwareDirectoryChannel> channels;

  FirmwareDirectoryChannel? channelById(String id) {
    for (final c in channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  factory FirmwareDirectory.fromJson(Map<String, dynamic> json) => FirmwareDirectory(
        channels: ((json['channels'] as List<dynamic>?) ?? [])
            .map((e) => FirmwareDirectoryChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// =============================================================================
// Abstract parser interface
// =============================================================================

abstract class FirmwareParser {
  FirmwareDirectory? _cache;

  String get directoryUrl;

  FirmwareDirectory? get cached => _cache;

  bool get hasCached => _cache != null;

  /// Fetches the directory JSON and caches the result.
  Future<FirmwareDirectory> fetch() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(directoryUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'qunleashed-app');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Server returned ${res.statusCode}', uri: Uri.parse(directoryUrl));
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      _cache = FirmwareDirectory.fromJson(json);
      return _cache!;
    } finally {
      client.close();
    }
  }

  /// Returns cached directory, fetching if needed.
  Future<FirmwareDirectory> get() async => _cache ?? await fetch();

  void clearCache() => _cache = null;

  /// Returns the channel for the given [FirmwareChannel].
  FirmwareDirectoryChannel? getChannel(FirmwareChannel channel) =>
      _cache?.channelById(channel.id);

  /// Returns the latest [FirmwareVersion] for the given channel.
  FirmwareVersion? getLatestVersion(FirmwareChannel channel) =>
      getChannel(channel)?.latest;

  /// Returns the changelog of the latest version for the given channel.
  String? getChangelog(FirmwareChannel channel) =>
      getLatestVersion(channel)?.changelog;

  /// Returns all download files for the latest version of the given channel.
  List<FirmwareFile> getDownloadFiles(FirmwareChannel channel) =>
      getLatestVersion(channel)?.files ?? [];

  /// Downloads [file] and saves it to [savePath].
  Future<void> downloadFile(FirmwareFile file, String savePath) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(file.url));
      req.headers.set(HttpHeaders.userAgentHeader, 'qunleashed-app');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Download failed: ${res.statusCode}', uri: Uri.parse(file.url));
      }
      final out = File(savePath).openWrite();
      await res.pipe(out);
    } finally {
      client.close();
    }
  }
}
