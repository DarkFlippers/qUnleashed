import 'package:flutter/foundation.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/config.dart';
import '../../../services/http/app_http.dart';

/// What is known about a firmware's directory.
///
/// One value rather than the pair of booleans this started as. All four
/// combinations that pair could express do occur - a retry in flight over an
/// earlier failure is both loading and failed - and the pair left every reader
/// to resolve that precedence for itself. [FirmwareRepository.stateFor]
/// resolves it once. #118.
enum FirmwareFetchState {
  /// A fetch is in flight, or nothing has settled yet.
  loading,

  /// The last attempt failed. An older directory may still be in hand.
  failed,

  /// A directory is in hand and the last attempt for it succeeded.
  ready;

  bool get isLoading => this == FirmwareFetchState.loading;
  bool get hasFailed => this == FirmwareFetchState.failed;
}

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

FirmwareDirectoryChannel buildCustomChannel() => FirmwareDirectoryChannel(
  id: kCustomFirmwareChannelId,
  title: l10n.firmwareChannelCustom,
  description: l10n.firmwareChannelCustomDescription,
  versions: const [],
);

enum UnleashedVariant {
  base,
  extraPacks,
  compact;

  /// The variant stored under [name], or null if this build has no such one.
  static UnleashedVariant? fromName(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final variant in values) {
      if (variant.name == raw) return variant;
    }
    return null;
  }
}

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

  /// Installs a directory as though it had just been fetched.
  ///
  /// For tests. The real one comes from the network, and without it the
  /// channel list is empty - so the controller's fallback, which is what
  /// decides whether a remembered channel survives, cannot be exercised at
  /// all. Marked fresh so a prefetch does not immediately replace it.
  @visibleForTesting
  void seedCache(FirmwareDirectory directory) {
    _cache = directory;
    _fetchedAt = DateTime.now();
  }

  /// Drops the cache so one test cannot inherit another's directory.
  @visibleForTesting
  void clearCache() {
    _cache = null;
    _fetchedAt = null;
  }

  bool get isFresh =>
      _cache != null &&
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) < _ttl;

  /// Where [fetch] gets its JSON.
  ///
  /// A seam rather than a direct call.
  ///
  /// `flutter_test` installs its own HttpOverrides, so an unreplaced fetch
  /// does not reach the network - it answers 400, which arrives as an
  /// `AppHttpException`. That is one network-shaped failure and nothing else,
  /// which is why the cases that need a socket error, a deadline or a document
  /// of the wrong shape replace this.
  ///
  /// Under the decode rather than over it, so a test can hand it a document of
  /// the wrong shape and have [FirmwareDirectory.fromJson] really run. Every
  /// field below it is an unchecked cast, so that is where a feed that changed
  /// shape actually breaks - a seam above the decode could only ever simulate
  /// the exception, never produce it.
  @visibleForTesting
  Future<dynamic> Function(Uri uri) fetchJson = AppHttp.getJson;

  Future<FirmwareDirectory> fetch() async {
    final json =
        await fetchJson(Uri.parse(directoryUrl)) as Map<String, dynamic>;
    final directory = FirmwareDirectory.fromJson(json);
    // Stamped after the decode, not before it. A feed whose shape changed
    // throws out of fromJson, and marking the previous cache fresh on the way
    // past left `isFresh` true for the whole TTL - so the next attempt was
    // short-circuited by a document that had just failed to parse.
    //
    // Not covered by a test: the difference only shows once the previous
    // stamp would itself have expired, and nothing here can move the clock
    // ten minutes. Every other freshness rule is pinned in
    // test/firmware_failure_test.dart.
    _fetchedAt = DateTime.now();
    return _cache = directory;
  }

  Future<FirmwareDirectory> get() async => isFresh ? _cache! : await fetch();

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
