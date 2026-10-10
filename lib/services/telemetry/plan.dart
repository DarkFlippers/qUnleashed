// What a build decides about reporting, before anything is sent.
//
// Its own file because it is the half of `Telemetry` that needs **nothing**:
// no DSN, no platform channel, no SDK. `test/telemetry_test.dart` exercises it
// directly, and keeping it here makes that property visible rather than
// asserted in a doc comment.
import '../build_identity.dart';

/// What a build would tell Sentry about itself, decided before anything is
/// sent.
///
/// A value rather than a block inside [Telemetry.start], so every rule in it
/// can be checked without a DSN, a platform channel or an SDK -
/// [0002](../../../docs/adr/0002-dependencies-are-passed-in.md). The three
/// reasons reporting does not happen are the interesting part, and all three
/// are decided here: no DSN compiled in, the switch off, or the switch on and
/// everything in place.
class TelemetryPlan {
  TelemetryPlan({
    required this.dsn,
    required this.shareLogs,
    required BuildStamp stamp,
    this.nativeDatabasePath,
  }) : release = stamp.sentryRelease,
       dist = stamp.build.isEmpty ? null : stamp.build,
       environment = stamp.channel.name,
       commit = stamp.commit,
       flipperlibCommit = stamp.flipperlibCommit,
       dartufbtCommit = stamp.dartufbtCommit;

  /// Public by design: a DSN identifies a project and authorises nothing but
  /// writing to it, which is why it ships inside the binary rather than coming
  /// from a secret store. `SENTRY_AUTH_TOKEN` is the one that must never be
  /// compiled in — see `docs/releasing.md`.
  final String dsn;

  final bool shareLogs;

  /// 0014 §5, and empty when the platform would not say what version this is.
  final String release;

  /// The build number, or **null** when the platform would not say.
  ///
  /// Nullable for the reason [tags] gives about an empty tag: `SentryOptions`
  /// takes `String?` here, so unset and empty are different on the wire, and
  /// `dist: ""` would group every report from an affected build under a
  /// distribution named empty string. ADR 0009.
  final String? dist;

  final String environment;

  final String commit;
  final String flipperlibCommit;
  final String dartufbtCommit;

  /// Where the native SDK keeps undelivered crashes, or null for its own
  /// default. `Telemetry._nativeDatabasePath` has why that default is wrong
  /// here.
  final String? nativeDatabasePath;

  /// Whether anything is sent at all.
  ///
  /// A missing DSN is the ordinary case rather than a fault: every local build
  /// has none unless the developer passed one, and the switch being off is the
  /// user's answer. Neither is reported as a failure, which is why [why]
  /// exists separately — the one line in the log is for someone wondering why
  /// a build they expected to report is silent.
  ///
  /// Derived from [why] rather than restating the condition. Written twice,
  /// a third reason added to [why] would leave this silently wrong - and
  /// nothing in `lib/` reads it, so nothing would have failed.
  bool get enabled => why == null;

  /// Why nothing is being sent, or null when something is.
  String? get why {
    if (dsn.isEmpty) return 'no DSN was compiled in';
    if (!shareLogs) return 'sharing is off in Settings';
    return null;
  }

  /// The tags 0014 §3 asks for, minus the ones nothing can fill.
  ///
  /// An empty commit is left out rather than sent as `''`. A tag present and
  /// blank reads, in a filter, as a build that was asked and had nothing to
  /// say, which is indistinguishable from a bug in the define — and the
  /// submodule tags are legitimately absent in a build made outside CI.
  Map<String, String> get tags => {
    if (commit.isNotEmpty) 'commit': commit,
    if (flipperlibCommit.isNotEmpty) 'flipperlib': flipperlibCommit,
    if (dartufbtCommit.isNotEmpty) 'dartufbt': dartufbtCommit,
  };
}
