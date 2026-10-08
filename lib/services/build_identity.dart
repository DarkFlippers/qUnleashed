import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

import 'logging.dart';

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

  /// `dev`, `release`, or `local` for a build nothing told.
  ///
  /// Three values and no more. Every build comes off `main`; `dev` is what the
  /// automatic builds are, `release` is what somebody cuts by hand, and `local`
  /// is a tree nobody else has. CI only ever says the first two.
  final String channel;

  bool get isDev => channel == BuildIdentity.devChannel;

  bool get isLocal => channel == BuildIdentity.localChannel;

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

  /// The version with the channel said in it: `0.14.1-dev`, `0.14.1`,
  /// `0.14.1-local`.
  ///
  /// This is the form for anything a person reads, and it is **not** what goes
  /// into `CFBundleShortVersionString`, which takes digits and periods and at
  /// most three integers - a build carrying `-dev` there fails App Store
  /// validation. 0014 §2 is the whole argument; the short of it is that the
  /// rule governs one field, so the suffix is kept everywhere else.
  ///
  /// A release says nothing, because a bare version already means "released"
  /// and a `-release` suffix is noise on the one build most people have.
  String get displayVersion {
    if (version.isEmpty) return 'unknown';
    if (isDev) return '$version-dev';
    if (isLocal) return '$version-local';
    return version;
  }

  /// `0.14.1+14001`, or just the version with no build number, or `unknown`
  /// with neither. The numeric form, for anything that compares versions.
  String get versionWithBuild {
    if (version.isEmpty) return 'unknown';
    return build.isEmpty ? version : '$version+$build';
  }

  /// One line naming this binary: `0.14.1-dev · 14001 · abc1234`.
  ///
  /// Widest to narrowest, so the part a reader almost always wants is first and
  /// the part that disambiguates is last. The channel is in the version rather
  /// than a field of its own - `0.14.1-dev · dev · abc1234` says it twice.
  ///
  /// A missing commit or build number is dropped rather than written as
  /// `unknown`: a local build has no commit, and a line saying so twice over
  /// reads as broken rather than as local.
  String get line {
    final parts = <String>[
      displayVersion,
      if (build.isNotEmpty) build,
      if (shortCommit.isNotEmpty) shortCommit,
    ];
    return parts.join(' · ');
  }

  /// The Sentry release, `qunleashed@0.14.1-dev+14001` — 0014 §5.
  ///
  /// Set explicitly rather than left to the SDK, whose default begins with the
  /// bundle ID and would split one build into five releases, one per platform.
  /// The suffix is what keeps a dev build and the shipped version from reading
  /// alike in a release list, which is the list most often read.
  String get sentryRelease {
    final suffix = build.isEmpty ? '' : '+$build';
    return 'qunleashed@$displayVersion$suffix';
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

  static const String devChannel = 'dev';
  static const String releaseChannel = 'release';
  static const String localChannel = 'local';

  /// Which channel built this, decided by the trigger and compiled in.
  ///
  /// From the trigger and not from the tag, which is 0014 §1 and matters more
  /// than it sounds. A push to `main` has no tag at all, so a dev build cannot
  /// derive this - and in this repository the prefix could not carry it even
  /// where there is one: every tag so far is `dev-*`, including the ones that
  /// were releases. `derive_version.sh` is the single place that turns a
  /// trigger into the answer.
  ///
  /// Defaults to [localChannel], which is the one value CI never sends: a
  /// build with no define is a developer's own run. Not null, because "which
  /// build is this" has an answer there too, and it is the answer most worth
  /// saying out loud - a report from `local` cannot be reproduced from
  /// anything in the repository.
  static const String channel = String.fromEnvironment(
    'QU_CHANNEL',
    defaultValue: localChannel,
  );

  /// The version and build number, read once and then remembered.
  ///
  /// Remembered because this crosses a platform channel and three surfaces want
  /// it. The failure is handled here rather than at each of them: a channel
  /// that does not answer must not cost the About screen, and must not cost the
  /// init of the thing whose job is to report failures.
  ///
  /// Which is also why it is only the version that can go missing. The channel
  /// and the three commits are `String.fromEnvironment` constants, so they are
  /// in the binary whether or not anything answers.
  ///
  /// **The value is cached, not the future**, and that distinction is
  /// load-bearing. A `static final Future` is captured by the zone that created
  /// it, so a continuation added from a different zone is queued on a zone
  /// nobody is running any more and never fires. One zone is the normal case
  /// and the bug is invisible there; two of them is every widget test, each
  /// with its own `FakeAsync`, and the symptom was an `await` here that simply
  /// never returned in whichever test did not happen to run first.
  static Future<BuildStamp> resolve() async => _cached ??= await _read();

  static BuildStamp? _cached;

  /// Forgets the cached value, so a test can read it again.
  ///
  /// Needed because the cache outlives a test: without this the second test to
  /// ask would be served a value read under the first one's mocks.
  @visibleForTesting
  static void debugForget() => _cached = null;

  static Future<BuildStamp> _read() async {
    var version = '';
    var build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (e) {
      // `caught` and not `warn`: the operation did not do what was asked, and
      // nobody needs alerting - what is left is still useful, since the commit
      // and the channel are compiled in and do not come from here. But it is
      // worth being readable afterwards, because it is the one thing that
      // makes every surface say `unknown`, and a reader looking at that line
      // would otherwise have nothing to explain it.
      LogService.caught('[Build] version unavailable: $e');
    }
    return BuildStamp(
      version: version,
      build: build,
      channel: channel,
      commit: commit,
      flipperlibCommit: flipperlibCommit,
      dartufbtCommit: dartufbtCommit,
    );
  }
}
