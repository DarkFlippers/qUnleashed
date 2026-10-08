import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

import 'logging.dart';

/// Which of the three channels produced a build.
///
/// Every build comes off `main`: [dev] is what the automatic builds are,
/// [release] is what somebody cuts by hand, and [local] is a tree nobody else
/// has. CI only ever says the first two.
///
/// An enum and not a `String`, because the failure direction of a bare one runs
/// the wrong way. `channel` arrives from a `String.fromEnvironment`, which can
/// hold anything; with a string, `isDev` and `isLocal` were both false for
/// anything unexpected, so a typo - `QU_CHANNEL=prod`, or `Dev` with a capital
/// - rendered the *bare* version and a Sentry release of `qunleashed@0.14.1`.
/// A developer's own tree would have impersonated a shipped build, which is the
/// opposite of what 0014 §1 defaults to `local` for. The shell guard does not
/// help: it only runs in CI.
enum BuildChannel {
  dev,
  release,
  local;

  /// Anything unrecognised is [local], and says so out loud.
  ///
  /// `local` rather than `release` because a define nobody expected is not a
  /// release, and because a report that arrives from `local` cannot be
  /// reproduced from anything in the repository - which is the honest reading
  /// of a build whose channel nobody can account for.
  static BuildChannel parse(String raw) {
    for (final channel in values) {
      if (channel.name == raw) return channel;
    }
    // Not `warn`: nothing is broken for the user, and the compiled-in default
    // is already the cautious one. But a CI build demoting itself to `local`
    // would be baffling without a line saying why.
    if (raw.isNotEmpty) {
      LogService.caught('[Build] unknown channel "$raw", reading it as local');
    }
    return local;
  }
}

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
    // Both come from one platform call, so one without the other is not a
    // state [BuildIdentity] produces - and it is the state the three
    // human-readable getters disagree about, since `versionWithBuild` drops
    // the number while `line` and `sentryRelease` keep it. Asserting the
    // dependency is cheaper than picking which of the three was right.
  }) : assert(
         version != '' || build == '',
         'a build number without a version is not a producible state',
       );

  /// `0.14.1`, or empty if the platform would not say.
  final String version;

  /// `108080`, or empty if the platform would not say.
  ///
  /// A counter, and nothing else: 0014 §6 makes it `100000 + commits × 10 +
  /// slot`, decoupled from [version] because §2 gives every dev build in a
  /// cycle the same name. So this orders builds and [commit] identifies the
  /// tree they came from, and both are worth quoting in a report.
  final String build;

  final BuildChannel channel;

  bool get isDev => channel == BuildChannel.dev;

  bool get isLocal => channel == BuildChannel.local;

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
  ///
  /// The suffix survives an unknown version. Only [version] crosses a platform
  /// channel; the channel is a compiled-in constant and cannot have failed, so
  /// `unknown-dev` keeps the half that is still true. Collapsing both to
  /// `unknown` threw away a fact nobody had lost.
  String get displayVersion {
    final name = version.isEmpty ? 'unknown' : version;
    return switch (channel) {
      BuildChannel.dev => '$name-dev',
      BuildChannel.local => '$name-local',
      BuildChannel.release => name,
    };
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

  /// The raw channel define, before [BuildChannel.parse] classifies it.
  ///
  /// From the trigger and not from the tag, which is 0014 §1 and matters more
  /// than it sounds: a push to `main` has no tag at all, so a dev build has
  /// nothing to derive a channel from. `derive_version.sh` is the single place
  /// that turns a trigger into the answer.
  ///
  /// Defaults to `local`, which is the one value CI never sends: a build with
  /// no define is a developer's own run. Worth saying out loud rather than
  /// left blank, because a report that arrives from `local` cannot be
  /// reproduced from anything in the repository.
  static const String channelName = String.fromEnvironment(
    'QU_CHANNEL',
    defaultValue: 'local',
  );

  /// The version and build number, read once and then remembered.
  ///
  /// Remembered because this crosses a platform channel and two surfaces want
  /// it today - the Tools line and the head of a copied log - with every Sentry
  /// event joining them once 0013 lands. The failure is handled here rather
  /// than at each of them: a channel that does not answer must not cost the
  /// About screen, and must not cost the Sentry init that 0013 puts in
  /// `_initCore`, which may never throw. Nothing calls this from `_initCore`
  /// yet, so that last constraint is anticipated rather than in force.
  ///
  /// Which is also why it is only the version that can go missing. The channel
  /// and the three commits are `String.fromEnvironment` constants, so they are
  /// in the binary whether or not anything answers.
  ///
  /// **The value is cached, not the future**, and that distinction is
  /// load-bearing. A `static final Future` created during one test is completed
  /// by that test's `FakeAsync`; if it is still pending when the test ends, the
  /// clock that would have completed it is gone and every later `await` of it
  /// hangs. One zone is the normal case and the bug is invisible there; every
  /// widget test has its own, and the symptom was an `await` here that never
  /// returned in whichever test did not happen to run first. Handing out an
  /// already-completed future is fine - `then` registers its callback in
  /// whatever zone is current when it is called - which is why caching the
  /// arrived value works and caching the future did not.
  ///
  /// Single-flight through [_inFlight], because `_cached ??= await …` tests the
  /// cache *before* the await: two callers racing - the Tools screen opening
  /// while the log screen copies - would both cross the channel, and on failure
  /// both log. `_remember` folds two consecutive identical bodies into `(2×)`,
  /// which reads to whoever gets the bug report as the app having failed twice.
  /// A `Completer` is safe where a `static final Future` is not: it is created
  /// inside the first caller's zone and does not outlive the value.
  static Future<BuildStamp> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;
    final pending = _inFlight;
    if (pending != null) return pending.future;

    final completer = Completer<BuildStamp>();
    _inFlight = completer;
    final stamp = await _read();
    _cached = stamp;
    _inFlight = null;
    completer.complete(stamp);
    return stamp;
  }

  static BuildStamp? _cached;
  static Completer<BuildStamp>? _inFlight;

  /// Forgets the cached value, so a test can read it again.
  ///
  /// Needed because the cache outlives a test: without this the second test to
  /// ask would be served a value read under the first one's mocks.
  @visibleForTesting
  static void debugForget() {
    _cached = null;
    _inFlight = null;
  }

  static Future<BuildStamp> _read() async {
    var version = '';
    var build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (e, st) {
      // `caught` and not `warn`: the operation did not do what was asked, and
      // nobody needs alerting - what is left is still useful, since the commit
      // and the channel are compiled in and do not come from here. But it is
      // worth being readable afterwards, because it is the one thing that
      // makes every surface say `unknown`, and a reader looking at that line
      // would otherwise have nothing to explain it.
      //
      // With the trace, through the house helper, because four different bugs
      // print almost identically here: a MissingPluginException from the
      // headless isolate a home-screen widget starts, a PlatformException from
      // the channel, and a TypeError or a cast failure from inside
      // package_info_plus' own parsing. The isolate one is the case that only
      // ever reproduces on a path CI does not cover, so losing its frames is
      // losing the only account of it.
      LogService.caught(
        '[Build] version unavailable: ${LogService.describe(e, st)}',
      );
    }
    return BuildStamp(
      version: version,
      build: build,
      channel: BuildChannel.parse(channelName),
      commit: commit,
      flipperlibCommit: flipperlibCommit,
      dartufbtCommit: dartufbtCommit,
    );
  }
}
