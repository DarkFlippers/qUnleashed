import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

import 'logging.dart';

/// Which of the three channels produced a build.
///
/// Every build comes off `main`: [dev] is what the automatic builds are,
/// [release] is what somebody cuts by hand, and [local] is a tree nobody else
/// has. CI only ever says the first two.
///
/// An enum rather than a `String` because the failure direction of a bare one
/// ran the wrong way: anything unexpected matched neither `dev` nor `local`, so
/// `QU_CHANNEL=prod` rendered the bare version and a developer's tree
/// impersonated a shipped build. The shell guard does not help; it only runs in
/// CI.
enum BuildChannel {
  dev,
  release,
  local;

  /// Anything unrecognised is [local], and says so out loud.
  ///
  /// `local` rather than `release` because a define nobody expected is not a
  /// release, and a report from `local` cannot be reproduced from anything in
  /// the repository — the honest reading of a channel nobody can account for.
  static BuildChannel parse(String raw) {
    for (final channel in values) {
      if (channel.name == raw) return channel;
    }
    // Not `warn`: nothing is broken for the user, and the default is already
    // the cautious one. But a CI build demoting itself to `local` would be
    // baffling without a line saying why.
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
/// without a platform channel or a `--dart-define`
/// ([0002](../../docs/adr/0002-dependencies-are-passed-in.md)).
class BuildStamp {
  const BuildStamp({
    required this.version,
    required this.build,
    required this.channel,
    required this.commit,
    required this.flipperlibCommit,
    required this.dartufbtCommit,
    // One platform call fills both or neither, so a number without a version
    // is not a state [BuildIdentity] produces.
  }) : assert(
         version != '' || build == '',
         'a build number without a version is not a producible state',
       );

  /// `0.14.1`, or empty if the platform would not say.
  final String version;

  /// `108080`, or empty if the platform would not say.
  ///
  /// A counter and nothing else: 0014 §6 makes it `100000 + commits × 10 +
  /// slot`, decoupled from [version] because §2 gives every dev build in a
  /// cycle the same name. So this orders builds, [commit] identifies the tree,
  /// and both are worth quoting in a report.
  final String build;

  final BuildChannel channel;

  /// The app's commit as a full SHA, or empty in a build nothing told.
  final String commit;

  /// The submodule commits, for the reason the app's own is here: a fault can
  /// be in either repository, and the superproject's commit does not say which
  /// revision of them it recorded. 0014 §3 carries three for that reason.
  final String flipperlibCommit;
  final String dartufbtCommit;

  /// Seven characters, which is what git abbreviates to.
  ///
  /// Empty in, empty out, so a caller tests the result rather than testing the
  /// input and then shortening it.
  static String _short(String sha) =>
      sha.length <= 7 ? sha : sha.substring(0, 7);

  String get shortCommit => _short(commit);

  /// The version with the channel said in it: `0.14.1-dev`, `0.14.1`,
  /// `0.14.1-local`.
  ///
  /// For anything a person reads, and **not** what goes into
  /// `CFBundleShortVersionString`, which takes digits and periods and at most
  /// three integers — a build carrying `-dev` there fails App Store validation.
  /// 0014 §2 has the argument; the rule governs one field, so the suffix is
  /// kept everywhere else.
  ///
  /// A release says nothing, because a bare version already means released.
  /// The suffix survives an unknown version: only [version] crosses a platform
  /// channel, so `unknown-dev` keeps the half that is still true.
  String get displayVersion {
    final name = version.isEmpty ? 'unknown' : version;
    return switch (channel) {
      BuildChannel.dev => '$name-dev',
      BuildChannel.local => '$name-local',
      BuildChannel.release => name,
    };
  }

  /// One line naming this binary: `0.14.1-dev · 14001 · abc1234`.
  ///
  /// Widest to narrowest, so the part a reader almost always wants is first.
  /// The channel is in the version rather than a field of its own, since
  /// `0.14.1-dev · dev` says it twice. A missing commit or number is dropped
  /// rather than written as `unknown`, which twice over reads as broken.
  String get line => [
    displayVersion,
    if (build.isNotEmpty) build,
    if (shortCommit.isNotEmpty) shortCommit,
  ].join(' · ');

  /// What a copied log opens with, so a paste into an issue identifies itself.
  ///
  /// `qUnleashed` spelled out, because this text leaves the app and lands
  /// somewhere with no idea what produced it. The submodules go on a second
  /// line, and only when there are any.
  String get header {
    final modules = <String>[
      if (flipperlibCommit.isNotEmpty) 'flipperlib ${_short(flipperlibCommit)}',
      if (dartufbtCommit.isNotEmpty) 'dartufbt ${_short(dartufbtCommit)}',
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
/// release tag that did not agree about what it meant.
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
  /// From the trigger and not from the tag, which is 0014 §1: a push to `main`
  /// has no tag, so a dev build has nothing to derive a channel from.
  /// `derive_version.sh` is the single place that turns a trigger into the
  /// answer.
  ///
  /// Defaults to `local`, the one value CI never sends — a build with no define
  /// is a developer's own run, and saying so is worth more than leaving it
  /// blank, because such a report cannot be reproduced from the repository.
  static const String channelName = String.fromEnvironment(
    'QU_CHANNEL',
    defaultValue: 'local',
  );

  /// The version and build number, read once and then remembered.
  ///
  /// Remembered because this crosses a platform channel and two surfaces want
  /// it. The failure is handled here rather than at each of them: a channel
  /// that does not answer must not cost the About screen, and must not cost
  /// the Sentry init 0013 puts in `_initCore`, which may never throw. Nothing
  /// calls this from `_initCore` yet, so that constraint is anticipated.
  ///
  /// Only the version can go missing. The channel and the three commits are
  /// `String.fromEnvironment` constants, in the binary whether or not anything
  /// answers.
  ///
  /// **The value is cached, not the future.** A `static final Future` created
  /// during one test is completed by that test's `FakeAsync`; if it is still
  /// pending when the test ends, the clock that would complete it is gone and
  /// every later `await` hangs. Handing out an already-arrived value has no
  /// such problem.
  ///
  /// Two callers arriving before the first read finishes will each cross the
  /// channel, which is idempotent and at worst logs the same failure twice.
  /// Guarding that would mean storing a future again, with the staleness above.
  static Future<BuildStamp> resolve() async => _cached ??= await _read();

  static BuildStamp? _cached;

  /// Forgets the cached value, so a test can read it again.
  ///
  /// The cache outlives a test: without this the second test to ask would be
  /// served a value read under the first one's mocks.
  @visibleForTesting
  static void debugForget() => _cached = null;

  static Future<BuildStamp> _read() async {
    var version = '';
    var build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (e, st) {
      // `caught` and not `warn`: the operation failed, nobody needs alerting,
      // and what is left still works. Worth reading afterwards because it is
      // the one thing that makes every surface say `unknown`.
      //
      // With the trace, because four bugs print almost identically here: a
      // MissingPluginException from the headless isolate a home-screen widget
      // starts, a PlatformException from the channel, and a TypeError or a
      // cast failure inside package_info_plus. The isolate one reproduces only
      // on a path CI does not cover, so its frames are the whole account.
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
