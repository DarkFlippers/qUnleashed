// Where a connect failure goes besides the screen.
//
// [ADR 0013 §2](../../../docs/adr/0013-observability-with-sentry.md) makes
// `classifyConnectError` one of its chokepoints: the kinds the classifier
// knows are a metric and a breadcrumb, an unknown string over BLE is an issue,
// and that issue list is then the platform strings it has not learned yet.
// `Telemetry._reportConnectFailure` is where that split lives, including why
// USB is counted rather than raised.
//
// The classifier itself is flipperlib's, and §3 does not let a submodule take
// a vendor dependency - so the hook is on this side of the call, in the app,
// and `lib/services/telemetry/` fills it.
import 'package:flipperlib/flipperlib.dart'
    show FlipperConnectErrorKind, classifyConnectError;

import '../logging.dart';

/// Which kind of connect attempt failed.
///
/// A closed vocabulary because it becomes a metric attribute, and a free
/// string there is a dimension nobody can group by two releases later. The
/// split is the one that changes what a failure *means*: an auto-dial nobody
/// asked for failing is not the same event as a tap that did not work, and the
/// picker's scan fails for the reasons a dial does while connecting to
/// nothing.
enum ConnectAttempt {
  /// A gesture: the picker, the device list, the CLI page's channel.
  manual,

  /// Something the app started: `LinkService`'s debounced auto-dial, its CLI
  /// restore, or the home-screen widget's cold link. No gesture is behind any
  /// of them, and the first two show the device page's hint rather than a
  /// dialog.
  auto,

  /// The picker's own scan.
  scan,
}

/// Where a classified connect failure goes, or nowhere.
typedef ConnectFailureSink = void Function(
  FlipperConnectErrorKind kind,
  Object error,
  StackTrace stack, {
  required ConnectAttempt attempt,
  required bool isBle,
});

/// What the metric calls a transport, in the one place that spells it.
///
/// Two files need the word - the attribute in `Telemetry` and the fallback log
/// line below - and they have to agree, so neither writes the ternary itself.
String transportLabel(bool isBle) => isBle ? 'ble' : 'usb';

/// Null until something installs one.
///
/// `lib/services/telemetry/` does, while reporting is on, and clears it again
/// when the switch goes off - the same one-way shape `guardedFailureSink` and
/// `LogService.keptSink` use, and for the same reason: this file knows there
/// may be a reader and nothing about who it is. ADR 0013 §2.
ConnectFailureSink? connectFailureSink;

/// Reports one failed connect attempt.
///
/// **Called from the `catch`, not from the dialog that shows the failure.**
/// `showConnectionFailedDialog` looks like the one place every one of these
/// passes through, and it is not: it is skipped when the widget is gone, it is
/// not on the auto paths at all - those become the device page's hint, or
/// nothing at all in the headless isolate - and `AutoConnectHintCard`
/// classifies inside `build`, so a report hung off the classifier there would
/// fire on every rebuild, which is the shape of #135/#136.
///
/// **A cancel is not a failure.** Three of the call sites swallow one before
/// they reach here (`LinkService._cancelledAndSaidSo`) and `_autoDial` checks
/// `_userDisconnectedKey` for the same reason; a user who calls off a dial
/// must not produce a count, and over BLE would otherwise produce an issue
/// titled after the library's own abort sentinel.
///
/// [isBle] is passed rather than derived. The thrown object does not say which
/// transport was being dialled, and every call site knows.
///
/// Does nothing at all while no sink is installed, which is every build with
/// no DSN and every user who turned the switch off.
void reportConnectFailure(
  Object error,
  StackTrace stack, {
  required ConnectAttempt attempt,
  required bool isBle,
}) {
  final sink = connectFailureSink;
  if (sink == null) return;
  try {
    sink(
      classifyConnectError(error),
      error,
      stack,
      attempt: attempt,
      isBle: isBle,
    );
  } catch (e, st) {
    // Two things in here can throw on an object the app did not make:
    // `classifyConnectError` calls `toString()` on it, which `guarded` already
    // documents as real enough to catch, and the sink is somebody else's code.
    // Neither may cost the caller its own failure handling - every call site
    // is a `catch` that still has a user waiting on a dialog or a hint.
    //
    // **The line carries what survived, not just what broke.** Two of the call
    // sites have no `LogService` line of their own, so for them this is the
    // only record that a connect failed at all - and a `toString()` that threw
    // takes the message with it, leaving the runtime type as the one fact left
    // about the original. The attempt and the transport say which of the paths
    // lost its report, and they also make the body differ between paths, which
    // `LogService._isNewLine` needs: one unvarying body folds to a single line
    // per session however many reports are lost.
    //
    // `caught` and not `warn`: nothing a user can act on, and nobody needs
    // alerting that reporting a failure failed.
    //
    // The one sink guard in the app with no re-entrancy latch of its own, and
    // it does not need one: `caught` reaches `LogService._announce`, which
    // holds `_announcing` for exactly this. Worth knowing before comparing
    // this with the four that do carry one.
    LogService.caught(
      '[Connect] a ${attempt.name} failure on ${transportLabel(isBle)} '
      '(${error.runtimeType}) was not reported: ${LogService.describe(e, st)}',
    );
  }
}
