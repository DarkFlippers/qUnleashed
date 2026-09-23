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

/// One thing a read could not use, and where in the document it sat.
typedef _Skip = ({String at, String problem});

/// How many distinct problems a message names before it gives up.
///
/// Twenty *kinds*, not twenty entries, because the list is grouped by problem
/// first. One renamed field is renamed in every entry that carries it - the
/// official directory ships 84 files today - so an ungrouped list spent every
/// slot on the same complaint and truncated away the one structural record
/// that said which channel had gone. There are about thirty kinds in all.
const int _maxNamed = 20;

/// Names each distinct problem once, with the places it happened.
///
/// A handful of places are worth naming in full - the same fault at the
/// document and at a channel is two different things to fix. Eighty-four of
/// them are not, and then the first is where a maintainer starts diffing the
/// feed against what this expected.
String _nameSkipped(List<_Skip> skipped) {
  final byProblem = <String, List<String>>{};
  for (final skip in skipped) {
    (byProblem[skip.problem] ??= <String>[]).add(skip.at);
  }
  final named = byProblem.entries
      .take(_maxNamed)
      .map(
        (e) => switch (e.value.length) {
          1 => '${e.value.single}: ${e.key}',
          <= 3 => '${e.key}: ${e.value.join(', ')}',
          _ => '${e.key} x${e.value.length} (first: ${e.value.first})',
        },
      )
      .join('; ');
  final rest = byProblem.length - _maxNamed;
  return rest > 0 ? '$named (and $rest more kinds)' : named;
}

/// A directory document that yielded nothing usable.
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
  FirmwareDirectoryUnreadable(List<String> skipped, this._said)
    : skipped = List.unmodifiable(skipped);

  /// A single reason, already its own summary.
  FirmwareDirectoryUnreadable.one(String skip)
    : skipped = List.unmodifiable([skip]),
      _said = skip;

  /// Everything that was dropped, in the order it was read, uncapped.
  ///
  /// [toString] is the capped, grouped form, because that is what
  /// `FirmwareRepository._recordFailure` logs and keeps as the reason it
  /// compares every later failure against. This list is for a caller that
  /// wants the detail, which today is the tests.
  final List<String> skipped;

  final String _said;

  @override
  String toString() =>
      'FirmwareDirectoryUnreadable: nothing in the document could be read '
      '(${skipped.length} skipped: $_said)';
}

/// Reads a directory feed, keeping whatever parses.
///
/// One bad field used to cost the whole document - every version of every
/// channel went with it, so an upstream type change took the directory-driven
/// half of the firmware page away from everyone at once (#133). Each entry is
/// now read on its own, and one that will not parse is skipped and named.
///
/// Two fields decide whether an entry survives: a channel's `id`, which is how
/// it is looked up, and a version's `version`, which titles the changelog page.
/// A file needs all four of its own. A title, description and changelog only
/// affect what is shown, so they fall back - and are still named, because
/// these are the fields a rename takes away in silence: `changelog` is what
/// decides the card offers a What's New button at all.
///
/// One rule runs at all three levels: a list that carried entries and produced
/// none, or that stopped being a list, or that is missing altogether, is
/// unreadable rather than empty. So a version whose files all failed is
/// dropped, which can empty its channel, which can empty the document. An
/// explicit null is the exception and means empty - the unleashed feed ships
/// `"versions": null` on its release-candidate channel today.
///
/// A document that produced no usable channel, having dropped something on the
/// way, throws [FirmwareDirectoryUnreadable]. Note "usable" rather than
/// "any": a channel kept empty by that null masks the loss of every channel
/// beside it, and that is the shape the live feed has.
class FirmwareDirectoryReader {
  /// Entries this could not use at all.
  final List<_Skip> _dropped = [];

  /// Fields that fell back. Counted apart from [_dropped], because a title
  /// that fell back costs nothing a user can see, and saying "3 unreadable
  /// entries" about a directory that is entirely usable sends a maintainer
  /// looking for three missing channels.
  final List<_Skip> _degraded = [];

  bool _used = false;

  /// What this read dropped and fell back on, or null if it was clean.
  ///
  /// `said` is for a person and is grouped and capped; `fingerprint` is the
  /// whole thing, and is what [FirmwareParser] compares to decide whether it
  /// has said this already. Comparing the capped form instead would let two
  /// unrelated documents whose first records matched suppress each other.
  ///
  /// The reader knows what there is to say; [FirmwareParser] decides whether
  /// to say it. That split is deliberate - the level and the "say it once"
  /// rule are reporting policy, and `FirmwareRepository._recordFailure` owns
  /// the same policy for the path where this one throws.
  ({String said, String fingerprint})? get summary {
    if (_dropped.isEmpty && _degraded.isEmpty) return null;
    final parts = [
      if (_dropped.isNotEmpty)
        'skipped ${_dropped.length} unreadable '
            '${_dropped.length == 1 ? 'entry' : 'entries'}: '
            '${_nameSkipped(_dropped)}',
      if (_degraded.isNotEmpty)
        '${_degraded.length} '
            '${_degraded.length == 1 ? 'field' : 'fields'} fell back: '
            '${_nameSkipped(_degraded)}',
    ];
    return (
      said: parts.join('; '),
      fingerprint: [
        ..._dropped.map((s) => '${s.at}: ${s.problem}'),
        ..._degraded.map((s) => '${s.at}: ${s.problem}'),
      ].join('\u0000'),
    );
  }

  FirmwareDirectory read(Object? json) {
    assert(!_used, 'one reader reads one document');
    _used = true;

    final document = _object(json);
    if (document == null) {
      throw FirmwareDirectoryUnreadable.one('document: not an object');
    }

    final channels = _each(document, 'channels', 'channels', _channel);
    // "No usable channel" rather than "no channel": a channel kept empty by an
    // explicit null still counts in the list, so asking whether the list is
    // empty would let it stand in for every channel that was lost beside it.
    final nothingUsable =
        channels == null || channels.every((c) => c.versions.isEmpty);
    if (nothingUsable && _dropped.isNotEmpty) {
      throw FirmwareDirectoryUnreadable([
        for (final s in _dropped) '${s.at}: ${s.problem}',
      ], _nameSkipped(_dropped));
    }
    return FirmwareDirectory(channels: channels ?? const []);
  }

  /// Reads `json[key]` as a list of objects, keeping whatever [parse] returns.
  ///
  /// Null means unreadable: the key was missing, the value was not a list, or
  /// it carried entries and produced none. An empty list means the feed said
  /// there is nothing here, which is an answer rather than a loss.
  ///
  /// Every level goes through here, so the rules that make the read tolerant
  /// are written once instead of three times that could drift apart.
  ///
  /// [parse] is handed [where] and the index rather than a finished path, so
  /// the path is built only where a skip is recorded. On a healthy feed every
  /// one of those strings would be discarded unread, and on the official
  /// directory there are 84 files to build them for.
  List<T>? _each<T>(
    Map<String, dynamic> json,
    String key,
    String where,
    T? Function(Map<String, dynamic> json, String where, int index) parse,
  ) {
    if (!json.containsKey(key)) {
      // Absent is not the same as null. A key the feed stopped sending is a
      // key the feed renamed, which is #133's own shape one level up.
      _dropped.add((at: where, problem: 'missing'));
      return null;
    }
    final raw = json[key];
    if (raw == null) return <T>[];
    if (raw is! List) {
      _dropped.add((at: where, problem: 'not a list'));
      return null;
    }

    final kept = <T>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = _object(raw[i]);
      if (entry == null) {
        _dropped.add((at: '$where[$i]', problem: 'not an object'));
        continue;
      }
      final one = parse(entry, where, i);
      if (one != null) kept.add(one);
    }
    if (kept.isEmpty && raw.isNotEmpty) return null;
    return kept;
  }

  FirmwareDirectoryChannel? _channel(
    Map<String, dynamic> json,
    String where,
    int index,
  ) {
    final id = _text(json['id']);
    if (id == null) {
      _dropped.add((at: '$where[$index]', problem: 'no id'));
      return null;
    }
    final at = '$where[$index]($id)';

    final versions = _each(json, 'versions', '$at.versions', _version);
    if (versions == null) {
      _dropped.add((at: at, problem: 'no version in it could be read'));
      return null;
    }

    return FirmwareDirectoryChannel(
      id: id,
      title: _presentation(json, 'title', at, or: id),
      description: _presentation(json, 'description', at, or: ''),
      versions: versions,
    );
  }

  FirmwareVersion? _version(
    Map<String, dynamic> json,
    String where,
    int index,
  ) {
    final version = _text(json['version']);
    if (version == null) {
      _dropped.add((at: '$where[$index]', problem: 'no version'));
      return null;
    }
    final at = '$where[$index]($version)';

    final files = _each(json, 'files', '$at.files', _file);
    if (files == null) {
      _dropped.add((at: at, problem: 'no file in it could be read'));
      return null;
    }

    final timestamp = json['timestamp'];
    return FirmwareVersion(
      version: version,
      changelog: _presentation(json, 'changelog', at, or: ''),
      // Nothing in the app reads this today, which is the only reason a bad
      // one is neither named nor fatal. Both stop being true the moment
      // something renders a release date.
      timestamp: timestamp is num ? timestamp.toInt() : 0,
      files: files,
    );
  }

  FirmwareFile? _file(Map<String, dynamic> json, String where, int index) {
    final url = _text(json['url']);
    final target = _text(json['target']);
    final type = _text(json['type']);
    // Trimmed, because `RemoteFirmwareSource._verifySha256` trims before it
    // decides: a checksum of spaces reads there as "this build publishes
    // none" and skips verifying an archive it is about to flash. Only the
    // variant URLs `UnleashedParser.getUpdatePackage` mints itself are
    // entitled to that.
    final rawSha = json['sha256'];
    final sha256 = rawSha is String ? _text(rawSha.trim()) : null;
    if (url == null || target == null || type == null || sha256 == null) {
      // Named one by one: a renamed field is renamed in every file entry of
      // the document, and one word repeated eighty-four times says nothing a
      // maintainer can diff a feed against.
      _dropped.add((
        at: '$where[$index]',
        problem:
            'bad ${[if (url == null) 'url', if (target == null) 'target', if (type == null) 'type', if (sha256 == null) 'sha256'].join(', ')}',
      ));
      return null;
    }
    return FirmwareFile(url: url, target: target, type: type, sha256: sha256);
  }

  /// The string a required field has to be: a string, and not blank.
  ///
  /// One rule for `id`, `version` and all four file fields, so "required
  /// scalar" is written once rather than at each of the three levels.
  String? _text(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

  /// A field that is only shown, with [or] standing in when the feed sent
  /// nothing usable.
  ///
  /// Absent and wrong-typed are recorded; blank is not. A blank description or
  /// changelog is the same value either way, and a blank title standing in as
  /// the id is what the picker wants - but a field that has *gone* is the feed
  /// changing under the app, and both live feeds send all three on every entry
  /// today.
  String _presentation(
    Map<String, dynamic> json,
    String field,
    String at, {
    required String or,
  }) {
    final value = json[field];
    final text = _text(value);
    if (text != null) return text;
    if (value == null) {
      _degraded.add((at: '$at.$field', problem: 'missing'));
    } else if (value is! String) {
      _degraded.add((at: '$at.$field', problem: 'not a string'));
    }
    return or;
  }

  /// A JSON object, or null for anything else.
  ///
  /// `jsonDecode` types every object as `Map<String, dynamic>`, and Dart's
  /// generics are covariant, so a literal written in a test satisfies this too
  /// however narrowly it was inferred - `Map<String, String>` included. A
  /// `Map<dynamic, dynamic>` does not, and is named "not an object"; nothing
  /// on this path produces one.
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
    _lastSaid = null;
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

  /// The last thing [_say] said about this feed, so one that is permanently
  /// odd is said once rather than on every refresh.
  String? _lastSaid;

  /// Says what a read dropped, unless this feed said the same thing last time.
  ///
  /// At error, for the reason `FirmwareRepository._recordFailure` draws the
  /// same line: no network is involved, so a skip is the feed changing shape
  /// under the app, and it lands on every user at once.
  ///
  /// The memory lives here rather than on the reader because a reader is built
  /// per fetch and this has to outlive one. `ensure` has many callers and no
  /// memory of its own, `refresh` skips the freshness check entirely, and
  /// `LogService` coalesces only consecutive identical bodies - which the two
  /// firmwares fetched by one `Future.wait` never are. A clean read forgets,
  /// so a fault that returns after a recovery is said again; `_recordFailure`
  /// clears `_failed` on a success for exactly that reason.
  ///
  /// Compared on the fingerprint rather than on what is printed: the printed
  /// form is grouped and capped, so two unrelated documents could share one.
  void _say(({String said, String fingerprint})? summary) {
    if (summary == null) {
      _lastSaid = null;
      return;
    }
    if (summary.fingerprint == _lastSaid) return;
    _lastSaid = summary.fingerprint;
    LogService.error('[Firmware] $directoryUrl: ${summary.said}');
  }

  Future<FirmwareDirectory> fetch() async {
    final reader = FirmwareDirectoryReader();
    final directory = reader.read(await fetchJson(Uri.parse(directoryUrl)));
    _say(reader.summary);
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
