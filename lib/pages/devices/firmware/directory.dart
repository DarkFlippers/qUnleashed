import 'package:flutter/foundation.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/config.dart';
import '../../../services/http/app_http.dart';
import '../../../services/logging.dart';

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
}

/// A directory document that yielded nothing at all.
///
/// Not a [FormatException]: the repository files those as the user's network,
/// and this is the opposite - the body parsed as JSON and then turned out not
/// to be a directory. It has to reach the card as a failure rather than as an
/// empty directory, because an empty one reads as "the server has no builds"
/// and stops the retry.
class FirmwareDirectoryUnreadable implements Exception {
  const FirmwareDirectoryUnreadable(this.skipped);

  /// What was dropped on the way, in the order it was read.
  final List<String> skipped;

  @override
  String toString() =>
      'FirmwareDirectoryUnreadable: nothing in the document could be read '
      '(${skipped.length} skipped: ${skipped.join('; ')})';
}

/// Reads a directory feed, keeping whatever parses.
///
/// One bad field used to cost the whole document - every channel of every
/// version went with it, so an upstream type change disabled the firmware
/// page for everyone at once (#133). Each entry is now read on its own, and
/// one that will not parse is skipped and named.
///
/// Only two fields are load-bearing: a channel's `id`, which is how it is
/// looked up, and a version's `version`, which is what the card compares and
/// shows. A title falls back to the id, a changelog and a timestamp to
/// nothing, and a file has to carry all four of its fields or it cannot be
/// downloaded. Everything else degrades: a version whose files all failed
/// keeps its place and simply cannot be installed, which `updatePackageFor`
/// already answers with null.
///
/// Nothing surviving is not degradation, and throws - see
/// [FirmwareDirectoryUnreadable].
class FirmwareDirectoryReader {
  final List<String> _skipped = [];

  /// What was dropped, in the order it was read.
  List<String> get skipped => List.unmodifiable(_skipped);

  FirmwareDirectory read(Map<String, dynamic> json) {
    final raw = json['channels'];
    if (raw != null && raw is! List) _skipped.add('channels: not a list');
    final entries = raw is List ? raw : const <dynamic>[];

    final channels = <FirmwareDirectoryChannel>[];
    for (var i = 0; i < entries.length; i++) {
      final channel = _channel(entries[i], i);
      if (channel != null) channels.add(channel);
    }

    // A document that carried channels and produced none is a document this
    // no longer understands, not a feed with nothing in it.
    if (channels.isEmpty && entries.isNotEmpty) {
      throw FirmwareDirectoryUnreadable(skipped);
    }
    return FirmwareDirectory(channels: channels);
  }

  /// Says once what the whole read dropped, or nothing at all.
  ///
  /// At error, for the reason `FirmwareRepository._recordFailure` draws the
  /// same line: no network is involved, so a skip is the feed changing shape
  /// under the app, and it breaks for every user at once.
  void report(String url) {
    if (_skipped.isEmpty) return;
    LogService.error(
      '[Firmware] $url: skipped ${_skipped.length} unreadable '
      '${_skipped.length == 1 ? 'entry' : 'entries'}: ${_skipped.join('; ')}',
    );
  }

  FirmwareDirectoryChannel? _channel(Object? raw, int index) {
    final json = _object(raw);
    if (json == null) {
      _skipped.add('channels[$index]: not an object');
      return null;
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      _skipped.add('channels[$index]: no id');
      return null;
    }

    final rawVersions = json['versions'];
    if (rawVersions != null && rawVersions is! List) {
      _skipped.add('$id.versions: not a list');
    }
    final entries = rawVersions is List ? rawVersions : const <dynamic>[];
    final versions = <FirmwareVersion>[];
    for (var i = 0; i < entries.length; i++) {
      final version = _version(entries[i], id, i);
      if (version != null) versions.add(version);
    }

    // A channel that carried versions and produced none is unreadable in the
    // same way a document with no channels is: keeping it would put an empty
    // channel on the card, which reads as a firmware with no builds rather
    // than one whose builds could not be read.
    if (versions.isEmpty && entries.isNotEmpty) {
      _skipped.add('$id: no version in it could be read');
      return null;
    }

    final title = json['title'];
    final description = json['description'];
    return FirmwareDirectoryChannel(
      id: id,
      title: title is String && title.isNotEmpty ? title : id,
      description: description is String ? description : '',
      versions: versions,
    );
  }

  FirmwareVersion? _version(Object? raw, String channel, int index) {
    final json = _object(raw);
    if (json == null) {
      _skipped.add('$channel[$index]: not an object');
      return null;
    }
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      _skipped.add('$channel[$index]: no version');
      return null;
    }

    final rawFiles = json['files'];
    if (rawFiles != null && rawFiles is! List) {
      _skipped.add('$channel $version: files is not a list');
    }
    final entries = rawFiles is List ? rawFiles : const <dynamic>[];
    final files = <FirmwareFile>[];
    for (var i = 0; i < entries.length; i++) {
      final file = _file(entries[i], '$channel $version', i);
      if (file != null) files.add(file);
    }

    final changelog = json['changelog'];
    final timestamp = json['timestamp'];
    return FirmwareVersion(
      version: version,
      changelog: changelog is String ? changelog : '',
      timestamp: timestamp is num ? timestamp.toInt() : 0,
      files: files,
    );
  }

  FirmwareFile? _file(Object? raw, String where, int index) {
    final json = _object(raw);
    if (json == null) {
      _skipped.add('$where file $index: not an object');
      return null;
    }
    final url = json['url'];
    final target = json['target'];
    final type = json['type'];
    final sha256 = json['sha256'];
    // All four or none: a file missing any of them cannot be downloaded or
    // checked, so keeping it would only push the failure to the flash.
    if (url is! String ||
        target is! String ||
        type is! String ||
        sha256 is! String) {
      _skipped.add('$where file $index: incomplete');
      return null;
    }
    return FirmwareFile(url: url, target: target, type: type, sha256: sha256);
  }

  /// A JSON object, whatever the decoder happened to type its keys as.
  Map<String, dynamic>? _object(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : null;
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
    final reader = FirmwareDirectoryReader();
    final directory = reader.read(json);
    reader.report(directoryUrl);
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
