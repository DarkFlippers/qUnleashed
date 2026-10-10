// Everything the SDK is told, and the scope it is told it on.
//
// Its own file because this is where ADR 0013 §6's privacy decisions are read
// off, and a reader looking for them was scrolling past the whole lifecycle to
// get there. Pure: options in, options mutated, nothing of `Telemetry`'s own
// state touched - which is why these are top-level functions rather than
// methods.
import 'package:sentry_flutter/sentry_flutter.dart';

import '../logging.dart';
import 'plan.dart';
import 'scrub_event.dart';

/// Everything the SDK is told, in one place so §6 can be read off it.
void configureOptions(SentryFlutterOptions options, TelemetryPlan plan) {
  options.dsn = plan.dsn;
  options.release = plan.release;
  // Null leaves the SDK's own default, which is the right fallback: a crash
  // report in an awkward place beats no crash report.
  options.nativeDatabasePath = plan.nativeDatabasePath;
  options.dist = plan.dist;
  options.environment = plan.environment;

  // §6.1, not collected. `attachScreenshot` is already the SDK's default;
  // it is written down anyway because a default that changes in a minor
  // version is not something a privacy decision should rest on.
  //
  // `attachViewHierarchy` is the one §6.1 names that is **not** set here. It
  // defaults to false, and the option is marked experimental - so touching
  // it raises `experimental_member_use`, which CI treats as fatal. Left at
  // its default, with the server-side rules in §6.3 as the backstop that
  // does not depend on an SDK default either way.
  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  // On by default, and off here because `LogService` feeds Sentry directly
  // (§2). Left on, every line a talking build prints would arrive a second
  // time as a breadcrumb, unscrubbed by anything in this file.
  options.enablePrintBreadcrumbs = false;

  // §6.2. Every event passes through the scrubber before it leaves.
  //
  // Three hooks, not one, because sentry 9 routes the three event classes
  // separately and §6.2's "runs before every event, breadcrumb, log and
  // transaction" was only true of the first. A log reaches
  // `beforeSendLog` and nothing else (`log_capture_pipeline.dart`); a
  // transaction reaches `beforeSendTransaction` and falls to `beforeSend`
  // only when that is unset. So without the other two, the Logs channel -
  // the highest-volume outbound channel in the feature - was held by a
  // single `Scrub.outbound` call in `_reportKept`, and span text by
  // per-call-site discipline.
  options.beforeSend = (event, hint) => scrubEvent(event);
  options.beforeSendTransaction = (transaction, hint) =>
      scrubTransaction(transaction);
  options.beforeSendLog = (log) => scrubLog(log);

  // Sentry Logs, which §2 feeds from `LogService`'s kept entries. Off by
  // default in this major and configured differently in 10 - which is the
  // one line §7's "10 is a version bump" now costs, and it says so.
  options.enableLogs = true;

  // §8: everything at 100%, revisited after a month of real volume. The
  // plan has the headroom and pay-as-you-go is capped at $0, so going over
  // drops events rather than producing a bill.
  //
  // This is also what makes the navigator observer do anything:
  // `isTracingEnabled()` is false while the rate is null, and a span with no
  // sampled transaction over it is discarded.
  options.tracesSampleRate = 1.0;

  // Off, and not because it is unwanted. Frame timings need
  // `SentryWidgetsFlutterBinding`, and `_initCore` installs Flutter's own -
  // swapping it would mean `main.dart` importing the SDK, which §2's import
  // rule forbids, and installing Sentry's binding in a build that reports
  // nothing is the thing 0013's Consequences asks to verify first. Left
  // false so the SDK does not warn about a binding it was never given.
  options.enableFramesTracking = false;

  // §3: or their frames are folded away as third-party, which is the
  // opposite of true - a fault in either is this project's to fix.
  options.addInAppInclude('flipperlib');
  options.addInAppInclude('dartufbt');

  // The SDK's own diagnostics follow QLOG rather than the build type, so a
  // release build made to talk talks about this too, and a debug run told to
  // be quiet is quiet.
  options.debug = LogService.printing;
}

/// Puts 0014 §3's commits on every event.
///
/// On the scope rather than in the options, because the SDK has no
/// options-level tag map - and the scope is the right place regardless: it
/// is synced to the native layer, so a native crash carries them too, which
/// is the event class that cannot be assembled in Dart at all.
Future<void> tagScope(TelemetryPlan plan) async {
  await Sentry.configureScope((scope) async {
    for (final tag in plan.tags.entries) {
      await scope.setTag(tag.key, tag.value);
    }
  });
}
