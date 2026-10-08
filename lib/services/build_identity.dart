import 'package:package_info_plus/package_info_plus.dart';

/// What a build says it is: version, build number, channel and the commits it
/// was built from.
///
/// A value rather than a set of statics, so the formatting below can be tested
/// without a platform channel or a `--dart-define` - the compiled-in halves are
/// read once, in [BuildIdentity.resolve], and passed in
/// ([0002](../../docs/adr/0002-dependencies-are-passed-in.md)).
class BuildStamp {
  const BuildStamp({
    required this.version,
    required this.build,
    required this.channel,
    required this.commit,
    required this.flipperlibCommit,
    required this.dartufbtCommit,
  });

  /// `0.14.1`, or empty if the platform would not say.
  final String version;

  /// `14001`, or empty if the platform would not say.
  ///
  /// Under the formula in place today this is derived from [version], so every
  /// build of one version carries the same number. 0014 §6 is what turns it
  /// into a counter; until then [commit] is the only thing that tells two
  /// builds apart, which is why the commit is shown beside this rather than
  /// instead of it.
  final String build;

  /// `dev`, `beta`, `release`, or `local` for a build cut from no tag.
  final String channel;

  /// The app's commit as a full SHA, or empty in a build nothing told.
  final String commit;

  /// The submodule commits, for the reason the app's own is here: a fault can
  /// be in either repository, and the superproject's commit does not say which
  /// revision of them it recorded. 0014 §3 carries three for that reason.
  final String flipperlibCommit;
  final String dartufbtCommit;

  /// Seven characters, which is what git abbreviates to and how a commit is
  /// quoted everywhere else.
  ///
  /// Empty in, empty out, so a caller tests the result rather than testing the
  /// input and then shortening it.
  static String short(String sha) =>
      sha.length <= 7 ? sha : sha.substring(0, 7);

  String get shortCommit => short(commit);

  /// `0.14.1+14001`, or just the version with no build number, or `unknown`
  /// with neither.
  String get versionWithBuild {
    if (version.isEmpty) return 'unknown';
    return build.isEmpty ? version : '$version+$build';
  }

  /// One line naming this binary: `0.14.1+14001 · dev · abc1234`.
  ///
  /// Widest to narrowest, so the part a reader almost always wants is first and
  /// the part that disambiguates is last. A missing commit is dropped rather
  /// than written as `unknown`: a local build has none, and a line saying so
  /// twice over reads as broken rather than as local.
  String get line {
    final parts = <String>[versionWithBuild, channel];
    if (shortCommit.isNotEmpty) parts.add(shortCommit);
    return parts.join(' · ');
  }

  /// What a copied log opens with, so a paste into an issue identifies itself.
  ///
  /// `qUnleashed` spelled out, because this text leaves the app and lands
  /// somewhere that has no idea what produced it. The submodules go on a second
  /// line, and only when there are any.
  String get header {
    final modules = <String>[
      if (flipperlibCommit.isNotEmpty) 'flipperlib ${short(flipperlibCommit)}',
      if (dartufbtCommit.isNotEmpty) 'dartufbt ${short(dartufbtCommit)}',
    ];
    return [
      'qUnleashed $line',
      if (modules.isNotEmpty) modules.join(' · '),
    ].join('\n');
  }
}

/// Reads the build's identity once and hands out the [BuildStamp].
///
/// One place, because [0014](../../docs/adr/0014-build-identity.md) asks for
/// one and because the alternative has already happened: three readers of the
/// release tag that did not agree about what it meant. The About screen, the
/// head of a copied log and - once 0013 lands - every Sentry event read this
/// rather than deriving it again.
///
/// Compiled in, not read from a file: a build has to be able to say what it is
/// without the network, without the filesystem, and in the headless isolate a
/// home-screen widget starts.
abstract final class BuildIdentity {
  static const String commit = String.fromEnvironment('QU_COMMIT');

  static const String flipperlibCommit = String.fromEnvironment(
    'QU_COMMIT_FLIPPERLIB',
  );

  static const String dartufbtCommit = String.fromEnvironment(
    'QU_COMMIT_DARTUFBT',
  );

  /// The tag the build was cut from, when it was cut from one.
  ///
  /// 0014 §1 replaces this with a compiled-in `QU_CHANNEL`, which is the same
  /// value without a regex in front of it. Until then [channelFromTag] parses
  /// it, here rather than in whichever widget happens to display it.
  static const String _releaseTag = String.fromEnvironment(
    'QUNLEASHED_RELEASE_TAG',
  );

  /// Which of the three channels [tag] names: `dev`, `release` or `local`.
  ///
  /// Three and not more. Every build comes off `main`; `dev` is what the
  /// automatic builds are, `release` is what somebody cuts by hand in GitHub,
  /// and `local` is a tree nobody else has. That is the whole set, and 0014 §1
  /// says the same: `dev-*` is `dev`, anything else is `release`.
  ///
  /// So the historical prefixes collapse rather than survive. `beta-0.11.2`,
  /// `alpha-0.8.4` and `wip-0.3.6` were all cut by hand, so all three are
  /// `release` — reading the prefix back out would be reporting the tagging
  /// convention of the day rather than how the build was made. What tells two
  /// builds apart is the version and the commit, not the word in front of the
  /// tag.
  ///
  /// `local` is a value and not null because "which build is this" has an
  /// answer for a developer's own run, and it is the answer most worth saying
  /// out loud: a report that arrives from `local` cannot be reproduced from
  /// anything in the repository.
  static String channelFromTag(String tag) {
    if (tag.isEmpty) return 'local';
    return tag.startsWith('dev-') ? 'dev' : 'release';
  }

  /// The version and build number, resolved once and cached.
  ///
  /// Cached because this crosses a platform channel and three surfaces want it.
  /// The failure is handled here rather than at each of them: a channel that
  /// does not answer must not cost the About screen, and must not cost the init
  /// of the thing whose job is to report failures.
  static Future<BuildStamp> resolve() => _stamp;

  static final Future<BuildStamp> _stamp = _read();

  static Future<BuildStamp> _read() async {
    var version = '';
    var build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {
      // Deliberately silent, and deliberately not a LogService call: this can
      // run before logging is up, and an unknown version is a worse line on the
      // About screen rather than a failure anybody can act on. What is left is
      // still useful - the commit is compiled in and does not come from here.
    }
    return BuildStamp(
      version: version,
      build: build,
      channel: channelFromTag(_releaseTag),
      commit: commit,
      flipperlibCommit: flipperlibCommit,
      dartufbtCommit: dartufbtCommit,
    );
  }
}
