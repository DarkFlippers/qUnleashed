import 'package:sentry_flutter/sentry_flutter.dart';

import '../build_identity.dart';
import '../guarded.dart';
import '../logging.dart';
import 'scrub.dart';
import 'settings.dart';

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
  }) : release = stamp.sentryRelease,
       dist = stamp.build,
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
  final String dist;
  final String environment;

  final String commit;
  final String flipperlibCommit;
  final String dartufbtCommit;

  /// Whether anything is sent at all.
  ///
  /// A missing DSN is the ordinary case rather than a fault: every local build
  /// has none unless the developer passed one, and the switch being off is the
  /// user's answer. Neither is reported as a failure, which is why [why]
  /// exists separately — the one line in the log is for someone wondering why
  /// a build they expected to report is silent.
  bool get enabled => dsn.isNotEmpty && shareLogs;

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

/// The one place in `lib/` that imports the Sentry SDK.
///
/// [ADR 0013 §2](../../../docs/adr/0013-observability-with-sentry.md) makes
/// this folder the boundary and `test/sentry_import_guard_test.dart` holds it.
/// Everything above keeps calling `LogService`, `guarded` and the connection
/// classifier; this turns what they already record into events.
///
/// Phase 1 of the rollout, which is errors and crashes. Tracing, Sentry Logs
/// and replay each arrive with their own phase, and nothing here enables them:
/// `tracesSampleRate` is left unset, so `SentryOptions.isTracingEnabled()` is
/// false and the automatic instrumentation samples nothing.
class Telemetry {
  Telemetry({required this.settings});

  /// The project to report to, or empty in a build nobody gave one.
  ///
  /// Compiled in rather than read from a file, for the reason 0014 gives about
  /// the build identity: this has to work with no network, no filesystem and
  /// in the headless isolate a home-screen widget starts.
  static const String dsn = String.fromEnvironment('QU_SENTRY_DSN');

  /// The switch this follows, exposed because the settings screen needs the
  /// same object: one owner for the value, one place that reacts to it.
  final DiagnosticsSettings settings;

  bool _running = false;

  /// Whether the SDK is up. False in every build without a DSN, which is
  /// every local build by default.
  bool get running => _running;

  /// Brings the SDK up if it should be, and **never throws**.
  ///
  /// `_initCore` awaits this on both entry points, and a throw there is not a
  /// setting that falls back - it is an app that never appears, on either
  /// path. CLAUDE.md. Two known throws are covered rather than guessed at:
  /// `SentryFlutter.init` raises `ArgumentError` on an empty DSN, which
  /// [TelemetryPlan.enabled] prevents reaching, and the native init can fail
  /// on a platform where the plugin is not registered, which the catch takes.
  ///
  /// Called after `LogService.initialize()`, so the handlers that are already
  /// in the two error slots are the ones Sentry finds and chains to. The order
  /// is load-bearing in that direction only: Sentry saves what it finds and
  /// calls it, so going in second keeps both. Going in first would mean
  /// `LogService` wrapping Sentry's handler, which also works - but then a
  /// failure inside `LogService.initialize` itself would reach the log and not
  /// Sentry, which is backwards.
  ///
  /// One call serves `main()` and `widgetMain()`: the home widget's engine is
  /// promoted into the full app rather than replaced, so the SDK that came up
  /// in the headless isolate is the one the app then uses.
  Future<void> start() async {
    if (_running) return;
    // Never gated on `loaded`. A preference store that will not open leaves
    // the switch at its default, which is on - DiagnosticsSettings.onLoadFailed
    // has the argument for why that direction is right now that this is not
    // consent.
    await settings.load();
    final plan = TelemetryPlan(
      dsn: dsn,
      shareLogs: settings.shareLogs,
      stamp: await BuildIdentity.resolve(),
    );
    final why = plan.why;
    if (why != null) {
      // `caught` rather than `warn`: nothing is broken and nobody needs
      // alerting, but a dev build that was supposed to be reporting and is
      // not would otherwise be silent about it in the one place anyone looks.
      LogService.caught('[Telemetry] not reporting: $why');
      return;
    }
    try {
      await SentryFlutter.init((options) => _configure(options, plan));
      await _tag(plan);
      guardedFailureSink = _reportGuarded;
      _running = true;
      settings.addListener(_reconcile);
    } catch (e, st) {
      LogService.warn('[Telemetry] init failed: ${LogService.describe(e, st)}');
    }
  }

  /// Shuts the SDK down, the handlers with it, and **never throws**.
  ///
  /// `Sentry.close()` also closes the native SDK, so turning the switch off
  /// stops the native crash handler and not only the Dart side - which is the
  /// whole of what §1 promises that switch does.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    guardedFailureSink = null;
    settings.removeListener(_reconcile);
    try {
      await Sentry.close();
    } catch (e, st) {
      LogService.warn(
        '[Telemetry] shutdown failed: ${LogService.describe(e, st)}',
      );
    }
  }

  /// Turns one `guarded()` failure into an issue.
  ///
  /// §2: `guarded` is one of the four chokepoints that already see every
  /// failure the app records, which is why this hooks it rather than adding
  /// `captureException` to several hundred catch sites.
  ///
  /// **Fingerprinted on the label and the error type**, which is the best
  /// grouping key the app has. Sentry's default would group on the stack, and
  /// every one of these shares a stack: `guarded`'s own `catchError`. So
  /// without this, one issue would hold every dropped future in the app. With
  /// it, "[Archive] syncing the category" failing with a `TimeoutException` is
  /// one issue and the same label failing with a `PlatformException` is
  /// another, which is the split somebody triaging would make by hand.
  ///
  /// The label is scrubbed. Every one is a literal at its call site today, so
  /// there is nothing in one to redact - but it is interpolated at a handful
  /// of them, and a label is the one field here that becomes an issue *title*.
  ///
  /// Nothing is awaited. `_record` is synchronous and must stay that way, and
  /// the SDK queues the send itself; `_guard` is what keeps a rejected capture
  /// from reaching the zone as an unlabelled `[uncaught]`.
  void _reportGuarded(
    String what,
    String verb,
    Object error,
    StackTrace stack,
  ) {
    final label = Scrub.outbound(what);
    _guard(
      () => Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          scope.fingerprint = [label, error.runtimeType.toString()];
          scope.setContexts('guarded', {'what': label, 'verb': verb});
        },
      ),
    );
  }

  /// Follows the switch after the first start.
  ///
  /// A listener rather than the setter calling in, so the dependency runs one
  /// way: this knows about the switch and the switch knows nothing about
  /// Sentry. The guard is `_running` against the setting rather than a flag of
  /// its own, so a notify that changed something else cannot restart the SDK.
  void _reconcile() {
    if (settings.shareLogs == _running) return;
    // `guarded` and not `unawaited`: a ChangeNotifier listener is a void
    // callback, and both of these are already no-throw - but a bare
    // `unawaited` here is the shape CLAUDE.md and #23 are about.
    _guard(settings.shareLogs ? start : stop);
  }

  /// `guarded` without the import, which would be circular: `guarded` logs
  /// through `LogService`, and this file is what `LogService` will eventually
  /// report *through*. Same contract - the returned future never rejects.
  void _guard(Future<void> Function() task) {
    Future.sync(task).catchError((Object e, StackTrace st) {
      LogService.error(
        '[Telemetry] following the switch failed: ${LogService.describe(e, st)}',
      );
    });
  }

  /// Everything the SDK is told, in one place so §6 can be read off it.
  void _configure(SentryFlutterOptions options, TelemetryPlan plan) {
    options.dsn = plan.dsn;
    options.release = plan.release;
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
    options.beforeSend = (event, hint) => scrubEvent(event);

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
  Future<void> _tag(TelemetryPlan plan) async {
    await Sentry.configureScope((scope) async {
      for (final tag in plan.tags.entries) {
        await scope.setTag(tag.key, tag.value);
      }
    });
  }
}

/// Takes the account name out of everything in [event] that carries free text.
///
/// Returns the same object. The protocol classes are mutable, and a `copyWith`
/// for each of them would be a second place to forget a field.
///
/// Four carriers, and the list is what §6.2 is checked against: the message, a
/// `SentryException`'s `value`, and a breadcrumb's `message` and `data`.
/// Deliberately **not** stack frames: Dart frames are `package:` and `dart:`
/// URIs with no home directory in them, and a native crash does not pass
/// through here at all - it is assembled below Dart, which is why §6.3 asks for
/// the same patterns as server-side rules.
///
/// `data` values are scrubbed only where they are already strings. A nested map
/// is left alone rather than walked: nothing the app puts in a breadcrumb has
/// one today, and a recursive walk over arbitrary JSON is a cost paid on every
/// event for a case that does not exist.
SentryEvent? scrubEvent(SentryEvent event) {
  final message = event.message;
  if (message != null) {
    message.formatted = Scrub.outbound(message.formatted);
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = Scrub.outbound(value);
  }

  for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
    final text = crumb.message;
    if (text != null) crumb.message = Scrub.outbound(text);
    final data = crumb.data;
    if (data == null) continue;
    for (final key in data.keys) {
      final value = data[key];
      if (value is String) data[key] = Scrub.outbound(value);
    }
  }

  return event;
}
