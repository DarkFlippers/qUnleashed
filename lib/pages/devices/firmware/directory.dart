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

/// How many of the skipped entries a message names before it gives up.
///
/// One renamed field is renamed in every entry that carries it: the official
/// directory ships 84 files today, so an uncapped join is a multi-kilobyte log
/// line - and `FirmwareRepository._recordFailure` keeps that whole string as
/// the key it compares every later failure against. Twenty names each distinct
/// thing that can go wrong several times over.
const int _maxNamed = 20;

String _nameSkipped(List<String> skipped) => skipped.length <= _maxNamed
    ? skipped.join('; ')
    : '${skipped.take(_maxNamed).join('; ')} '
          '(and ${skipped.length - _maxNamed} more)';

/// A directory document that yielded nothing at all.
///
/// Not a [FormatException]: the repository files those as the user's network,
/// and this is the opposite - the body parsed as JSON and then turned out not
/// to be a directory. Returning an empty directory instead would reach the
/// card as a success: `stateFor` reads ready, the channel list falls through
/// to the custom one and the button offers "pick a file to install", and the
/// empty result is cached and stamped fresh so nothing is fetched again for
/// ten minutes at a time. Throwing is what records the failure, puts CAN'T
/// CHECK on the card, and leaves the next `ensure` free to retry.
class FirmwareDirectoryUnreadable implements Exception {
  const FirmwareDirectoryUnreadable(this.skipped);

  /// What was dropped on the way, in the order it was read.
  ///
  /// Uncapped, unlike [toString]: a test reads this, and the cap exists for
  /// what gets logged and compared.
  final List<String> skipped;

  @override
  String toString() =>
      'FirmwareDirectoryUnreadable: nothing in the document could be read '
      '(${skipped.length} skipped: ${_nameSkipped(skipped)})';
}

/// Reads a directory feed, keeping whatever parses.
///
/// One bad field used to cost the whole document - every version of every
/// channel went with it, so an upstream type change took the directory-driven
/// half of the firmware page away from everyone at once (#133). Each entry is
/// now read on its own, and one that will not parse is skipped and named.
///
/// Only two fields are load-bearing: a channel's `id`, which is how it is
/// looked up, and a version's `version`, which is what decides the entry is
/// worth keeping and what titles the changelog page. A title falls back to the
/// id, a changelog and a description to nothing, and a file has to carry all
/// four of its fields, non-empty, or it is not one this can install. Whatever
/// is dropped is named either way.
///
/// One rule runs at all three levels: a list that carried entries and produced
/// none, or that stopped being a list at all, is unreadable rather than empty.
/// So a version whose files all failed is dropped, which can empty its
/// channel, which can empty the document - and an empty document throws, see
/// [FirmwareDirectoryUnreadable]. Keeping such a version is worse than it
/// looks: `UnleashedParser.getDisplayVersion` answers null for one with no
/// installable file, while the fetch itself counts as a success, and the card
/// then reads NO UPDATE - telling someone their firmware is current on the
/// strength of a document it could not read. That claim is what #118 removed.
///
/// A list the feed left out or set to null is a different answer and is kept
/// as empty: the unleashed feed ships `"versions": null` on its
/// release-candidate channel today.
class FirmwareDirectoryReader {
  final List<String> _skipped = [];

  /// The last report made under each tag, so a feed that is permanently odd
  /// is said once rather than on every refresh.
  ///
  /// `FirmwareParser.fetch` builds a reader per fetch, so the memory has to
  /// outlive the instance. `FirmwareRepository._recordFailure` carries the
  /// same mechanism and the argument for it: `ensure` has many callers and no
  /// memory of its own, `refresh` skips the freshness check entirely, and
  /// `LogService` coalesces only consecutive identical bodies - which the two
  /// firmwares fetched by one `Future.wait` never are.
  static final Map<String, String> _lastReported = {};

  /// Forgets what has been said, so one test cannot silence another's report.
  @visibleForTesting
  static void forgetReports() => _lastReported.clear();

  FirmwareDirectory read(Object? json) {
    final document = _object(json);
    if (document == null) {
      throw const FirmwareDirectoryUnreadable(['document: not an object']);
    }
    final channels = _each(document['channels'], 'channels', _channel);
    if (channels.lostEverything) {
      throw FirmwareDirectoryUnreadable(List.of(_skipped));
    }
    return FirmwareDirectory(channels: channels.kept);
  }

  /// Says once what the whole read dropped, or nothing at all.
  ///
  /// At error, for the reason `FirmwareRepository._recordFailure` draws the
  /// same line: no network is involved, so a skip is the feed changing shape
  /// under the app, and it affects every user at once. [tag] carries the
  /// bracketed source, the way `PrefsReader.report` takes it.
  void report(String tag) {
    if (_skipped.isEmpty) return;
    final body = _nameSkipped(_skipped);
    if (_lastReported[tag] == body) return;
    _lastReported[tag] = body;
    LogService.error(
      '$tag: skipped ${_skipped.length} unreadable '
      '${_skipped.length == 1 ? 'entry' : 'entries'}: $body',
    );
  }

  /// Reads [raw] as a list of JSON objects, keeping whatever [parse] returns.
  ///
  /// Every level goes through here, so the four things that make the read
  /// tolerant are written once: a list that is not one, an entry that is not
  /// an object, an entry [parse] rejected, and the one case that is not
  /// degradation at all.
  ///
  /// [where] is the path to this list; an entry's own path is `where[i]`, and
  /// that is what names every skip below it. Two channels sharing an id
  /// therefore still produce records that can be told apart.
  ({List<T> kept, bool lostEverything}) _each<T>(
    Object? raw,
    String where,
    T? Function(Map<String, dynamic> json, String at) parse,
  ) {
    if (raw is! List) {
      // Absent or null is an answer - the feed saying this level has nothing.
      // Any other type is the feed changing shape under the app.
      if (raw == null) return (kept: <T>[], lostEverything: false);
      _skipped.add('$where: not a list');
      return (kept: <T>[], lostEverything: true);
    }
    final kept = <T>[];
    for (var i = 0; i < raw.length; i++) {
      final at = '$where[$i]';
      final json = _object(raw[i]);
      if (json == null) {
        _skipped.add('$at: not an object');
        continue;
      }
      final one = parse(json, at);
      if (one != null) kept.add(one);
    }
    return (kept: kept, lostEverything: kept.isEmpty && raw.isNotEmpty);
  }

  FirmwareDirectoryChannel? _channel(Map<String, dynamic> json, String at) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      _skipped.add('$at: no id');
      return null;
    }
    final where = '$at($id)';

    final versions = _each(json['versions'], '$where.versions', _version);
    if (versions.lostEverything) {
      _skipped.add('$where: no version in it could be read');
      return null;
    }

    final title = json['title'];
    final description = json['description'];
    // Named rather than quietly defaulted. The description is rendered under
    // the channel in the picker, so a feed that renames it takes text off the
    // screen, and falling back in silence leaves nothing to find.
    _notAString(where, 'title', title);
    _notAString(where, 'description', description);
    return FirmwareDirectoryChannel(
      id: id,
      title: title is String && title.isNotEmpty ? title : id,
      description: description is String ? description : '',
      versions: versions.kept,
    );
  }

  FirmwareVersion? _version(Map<String, dynamic> json, String at) {
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      _skipped.add('$at: no version');
      return null;
    }
    final where = '$at($version)';

    final files = _each(json['files'], '$where.files', _file);
    if (files.lostEverything) {
      _skipped.add('$where: no file in it could be read');
      return null;
    }

    final changelog = json['changelog'];
    // `changelog` decides whether the card offers a WHAT'S NEW button at all,
    // so a feed that renames it makes a control disappear.
    _notAString(where, 'changelog', changelog);
    final timestamp = json['timestamp'];
    return FirmwareVersion(
      version: version,
      changelog: changelog is String ? changelog : '',
      // Nothing in the app reads this today, which is the only reason a bad
      // one is neither named nor fatal. Both stop being true the moment
      // something renders a release date.
      timestamp: timestamp is num ? timestamp.toInt() : 0,
      files: files.kept,
    );
  }

  FirmwareFile? _file(Map<String, dynamic> json, String at) {
    final url = json['url'];
    final target = json['target'];
    final type = json['type'];
    final sha256 = json['sha256'];
    // All four, non-empty, or none. An empty `sha256` is the sharp one:
    // `RemoteFirmwareSource` reads it as "this build publishes no checksum"
    // and skips verifying an archive it is about to flash, which only the
    // variant URLs it mints itself are entitled to.
    if (url is String &&
        url.isNotEmpty &&
        target is String &&
        target.isNotEmpty &&
        type is String &&
        type.isNotEmpty &&
        sha256 is String &&
        sha256.isNotEmpty) {
      return FirmwareFile(url: url, target: target, type: type, sha256: sha256);
    }
    // Named one by one: a renamed field is renamed in every file entry of the
    // document, and `incomplete` eighty-four times says nothing a maintainer
    // can diff a feed against.
    final bad = [
      if (url is! String || url.isEmpty) 'url',
      if (target is! String || target.isEmpty) 'target',
      if (type is! String || type.isEmpty) 'type',
      if (sha256 is! String || sha256.isEmpty) 'sha256',
    ];
    _skipped.add('$at: bad ${bad.join(', ')}');
    return null;
  }

  /// Names a field the feed sent as something other than a string.
  ///
  /// Absent is left alone: a field the feed never carried is not a change.
  void _notAString(String where, String field, Object? value) {
    if (value != null && value is! String) {
      _skipped.add('$where.$field: not a string');
    }
  }

  /// A JSON object, or null for anything else.
  ///
  /// `jsonDecode` types every object as `Map<String, dynamic>`, and Dart's
  /// generics are covariant, so a literal written in a test satisfies this too
  /// however narrowly it was inferred - `Map<String, String>` included. The
  /// `cast` this used to do was therefore unreachable in effect, and worse
  /// than nothing: a cast view checks on access, so iterating one would throw
  /// from inside the one class whose whole job is not to.
  Map<String, dynamic>? _object(Object? raw) =>
      raw is Map<String, dynamic> ? raw : null;
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
  /// the wrong shape and have [FirmwareDirectoryReader] really run on it. A
  /// seam above the decode could only ever stand in for what a changed feed
  /// does; this one produces it.
  @visibleForTesting
  Future<dynamic> Function(Uri uri) fetchJson = AppHttp.getJson;

  Future<FirmwareDirectory> fetch() async {
    final reader = FirmwareDirectoryReader();
    final directory = reader.read(await fetchJson(Uri.parse(directoryUrl)));
    reader.report('[Firmware] $directoryUrl');
    // Stamped after the decode, not before it. A feed whose shape changed
    // throws out of the read, and marking the previous cache fresh on the way
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
