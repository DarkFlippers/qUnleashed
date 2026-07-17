import '../../../config.dart';
import '../../../services/http/app_http.dart';

enum FirmwareChannel {
  release,
  releaseCandidate,
  development;

  String get id => switch (this) {
    FirmwareChannel.release => 'release',
    FirmwareChannel.releaseCandidate => 'release-candidate',
    FirmwareChannel.development => 'development',
  };

  Set<String> get aliases => switch (this) {
    FirmwareChannel.release => const {'release', 'stable'},
    FirmwareChannel.releaseCandidate => const {
      'release-candidate',
      'release_candidate',
      'rc',
      'candidate',
    },
    FirmwareChannel.development => const {'development', 'dev'},
  };

  static FirmwareChannel? fromId(String? rawId) {
    final id = rawId?.trim().toLowerCase();
    if (id == null || id.isEmpty) return null;
    for (final channel in FirmwareChannel.values) {
      if (channel.aliases.contains(id)) return channel;
    }
    return null;
  }
}

const kCustomFirmwareChannelId = 'custom';

FirmwareDirectoryChannel buildCustomChannel() => const FirmwareDirectoryChannel(
  id: kCustomFirmwareChannelId,
  title: 'Custom',
  description: 'Install firmware from a local .tgz archive',
  versions: [],
);

enum UnleashedVariant { base, extraPacks, compact }

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

  FirmwareFile? updatePackageFor(String target) {
    for (final f in files) {
      if (f.type == 'update_tgz' && f.target == target) return f;
    }
    return null;
  }

  factory FirmwareVersion.fromJson(Map<String, dynamic> json) =>
      FirmwareVersion(
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
  bool get hasVersions => versions.isNotEmpty;

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
    final normalized = FirmwareChannel.fromId(id);
    for (final c in channels) {
      if (c.id == id) return c;
      if (normalized != null && FirmwareChannel.fromId(c.id) == normalized) {
        return c;
      }
    }
    return null;
  }

  factory FirmwareDirectory.fromJson(Map<String, dynamic> json) =>
      FirmwareDirectory(
        channels: ((json['channels'] as List<dynamic>?) ?? [])
            .map(
              (e) =>
                  FirmwareDirectoryChannel.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
}

FirmwareParser parserForEntry(FirmwareEntry entry) => switch (entry.shortName) {
  'ofw' => OfwParser.instance,
  'unlshd' => UnleashedParser.instance,
  _ => OfwParser.instance,
};

abstract class FirmwareParser {
  static const Duration _ttl = Duration(minutes: 10);

  FirmwareDirectory? _cache;
  DateTime? _fetchedAt;

  String get directoryUrl;

  FirmwareDirectory? get cached => _cache;
  bool get hasCached => _cache != null;

  bool get isFresh =>
      _cache != null &&
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) < _ttl;

  Future<FirmwareDirectory> fetch() async {
    final json =
        await AppHttp.getJson(Uri.parse(directoryUrl)) as Map<String, dynamic>;
    _fetchedAt = DateTime.now();
    return _cache = FirmwareDirectory.fromJson(json);
  }

  Future<FirmwareDirectory> get() async =>
      isFresh ? _cache! : await fetch();

  FirmwareVersion? getLatestVersionById(String channelId) =>
      _cache?.channelById(channelId)?.latest;
}

class OfwParser extends FirmwareParser {
  OfwParser._();
  static final OfwParser instance = OfwParser._();

  @override
  String get directoryUrl =>
      'https://update.flipperzero.one/firmware/directory.json';
}

class UnleashedParser extends FirmwareParser {
  UnleashedParser._();
  static final UnleashedParser instance = UnleashedParser._();

  @override
  String get directoryUrl => 'https://up.unleashedflip.com/directory.json';

  FirmwareFile? getUpdatePackage(
    String channelId, {
    String target = 'f7',
    UnleashedVariant variant = UnleashedVariant.base,
  }) {
    final base = getLatestVersionById(channelId)?.updatePackageFor(target);
    if (base == null) return null;

    final channel = FirmwareChannel.fromId(channelId);
    if (variant == UnleashedVariant.base) return base;
    if (channel != FirmwareChannel.release &&
        channel != FirmwareChannel.development) {
      return null;
    }

    final suffix = variant == UnleashedVariant.compact ? 'c' : 'e';
    return FirmwareFile(
      url: _buildVariantUrl(base.url, suffix),
      target: base.target,
      type: base.type,
      sha256: '',
    );
  }

  String? getDisplayVersion(
    String channelId, {
    String target = 'f7',
    UnleashedVariant variant = UnleashedVariant.base,
  }) {
    final file = getUpdatePackage(channelId, target: target, variant: variant);
    if (file == null) return null;
    return _extractVersionFromUrl(file.url);
  }

  static String _buildVariantUrl(String baseUrl, String suffix) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;

    final segments = uri.pathSegments.toList();
    if (segments.isEmpty) return baseUrl;

    final fileName = segments.removeLast();
    final match = RegExp(
      r'^(flipper-z-[^-]+-update-[^.]+)(\.tgz)$',
    ).firstMatch(fileName);
    if (match == null) return baseUrl;

    final variantFileName = '${match.group(1)}$suffix${match.group(2)}';
    return uri
        .replace(pathSegments: <String>['fw_extra_apps', variantFileName])
        .toString();
  }

  static String? _extractVersionFromUrl(String url) {
    final fileName =
        Uri.tryParse(url)?.pathSegments.last ?? url.split('/').last;
    final match = RegExp(
      r'^flipper-z-[^-]+-update-([^.]+)\.tgz$',
    ).firstMatch(fileName);
    return match?.group(1);
  }
}
