import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel;
import 'package:flutter/widgets.dart' show NavigatorObserver;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../build_identity.dart';
import '../guarded.dart';
import '../http/app_http.dart';
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

/// The one place in `lib/` that imports the Sentry SDK.
///
/// [ADR 0013 §2](../../../docs/adr/0013-observability-with-sentry.md) makes
/// this folder the boundary and `test/sentry_import_guard_test.dart` holds it.
/// Everything above keeps calling `LogService`, `guarded` and the connection
/// classifier; this turns what they already record into events.
///
/// Phases 1 and 2 of the rollout: errors, crashes, Sentry Logs, breadcrumbs
/// and tracing. Replay is phase 3 and nothing here enables it - both of its
/// sample rates are left at the SDK's zero, which §6.4's gate is what stands
/// in front of.
///
/// This paragraph said the opposite until phase 2 landed and made it false.
/// ADR 0013's own status block is the current account of what is built; this
/// one is here so a reader of the class knows which phases its options
/// belong to.
/// How the SDK is brought up. `SentryFlutter.init` unless a test says
/// otherwise.
typedef SentryInit = Future<void> Function(
  void Function(SentryFlutterOptions) configure,
);

/// How it is shut down. `Sentry.close` unless a test says otherwise.
typedef SentryShutdown = Future<void> Function();

class Telemetry {
  /// Follows [settings] from construction, not from a successful [start].
  ///
  /// The listener used to go on inside `start()`'s success block and come off
  /// in `stop()`, which made the switch **one-way, once, per process**: the
  /// §1 notice's **Turn it off** called `stop()`, which removed the listener,
  /// so turning it back on afterwards did nothing at all - and a launch whose
  /// stored answer was already off returned before registering anything, so
  /// the same was true for the whole session. The row showed on, the
  /// preference persisted as on, and nothing reported until a restart.
  ///
  /// Registering here instead means the listener's lifetime is the object's.
  /// `_running` carries whether the SDK is up; it must not also carry whether
  /// anybody is watching the switch.
  Telemetry({
    required this.settings,
    String? dsn,
    SentryInit? init,
    SentryShutdown? shutdown,
  }) : dsn = dsn ?? compiledDsn,
       _init = init ?? SentryFlutter.init,
       _shutdown = shutdown ?? Sentry.close {
    settings.addListener(_reconcile);
  }

  /// The project a shipped build reports to, or empty in a build nobody gave
  /// one.
  ///
  /// Compiled in rather than read from a file, for the reason 0014 gives about
  /// the build identity: this has to work with no network, no filesystem and
  /// in the headless isolate a home-screen widget starts.
  static const String compiledDsn = String.fromEnvironment('QU_SENTRY_DSN');

  /// The project this instance reports to.
  ///
  /// Overridable because [compiledDsn] is a `String.fromEnvironment`, and no
  /// `--dart-define` reaches `flutter test` - so without a seam `start()`,
  /// `stop()` and `_reconcile` can never execute in a test, which is how a
  /// one-way privacy switch shipped unnoticed. ADR 0002 prefers the parameter
  /// anyway.
  final String dsn;

  /// The switch this follows, exposed because the settings screen needs the
  /// same object: one owner for the value, one place that reacts to it.
  final DiagnosticsSettings settings;

  /// Both are seams for one reason: `SentryFlutter.init` and `Sentry.close`
  /// are statics that bring a native layer up and down, so without them
  /// `start()`, `stop()` and `_reconcile` cannot run in a test at all - and
  /// that is how a privacy switch that only worked once per process, an init
  /// failure that left reporting on and unstoppable, and a shutdown failure
  /// that claimed success all shipped unnoticed in the same branch.
  ///
  /// A test's `init` is handed the same configure callback the SDK would get,
  /// so the options block is checkable too rather than taken on trust.
  final SentryInit _init;
  final SentryShutdown _shutdown;

  bool _running = false;

  /// Whether a start or a stop is in flight.
  ///
  /// `start()` awaits `settings.load()`, and a successful read calls
  /// `notifyListeners()` - which reaches [_reconcile], which compares the
  /// setting against `_running`. `_running` is still false at that point, so
  /// without this flag `_reconcile` starts a **second** `start()` on top of
  /// the first and the SDK is initialised twice. The `if (_running) return`
  /// guard cannot catch it, because the flag it reads is set at the end of the
  /// thing it is trying to guard.
  ///
  /// Found by the first test ever written against `start()`.
  bool _settling = false;

  /// Whether the SDK is up. False in every build without a DSN, which is
  /// every local build by default.
  bool get running => _running;

  /// What `MaterialApp.navigatorObservers` is given.
  ///
  /// Empty in a build with no DSN, so an app nobody is reporting from carries
  /// no observer at all.
  ///
  /// `late final` is what makes it one observer for the process, and that is
  /// the reason that matters: `MaterialApp` is rebuilt on every theme and
  /// locale change and reads this list each time, so a getter that built one
  /// would start a new trace on every accent colour. This used to say the list
  /// was read before the user could reach the Diagnostics switch, which is
  /// true and is not what protects it - `app.dart` had the right reason on the
  /// same field.
  ///
  /// Turning reporting off closes the hub rather than removing the observer,
  /// and its calls become no-ops; that is the one piece of this that keeps an
  /// object alive while switched off, and it holds no data.
  ///
  /// A `NavigatorObserver` rather than the SDK's own type, so `app.dart` takes
  /// a Flutter type and nothing above this folder names Sentry.
  late final List<NavigatorObserver> navigatorObservers = configured
      ? [
          SentryNavigatorObserver(
            // A trace per screen rather than one per process. The default is
            // one trace for the whole session, which on a phone app that stays
            // open for days puts every span and breadcrumb under a single id -
            // readable for a web page load, useless here.
            enableNewTraceOnNavigation: true,
          ),
        ]
      : const [];

  /// Whether this instance has a DSN at all. Says nothing about the switch.
  bool get configured => dsn.isNotEmpty;

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
    if (_running || _settling) return;
    _settling = true;
    _settlingToward = true;
    try {
      // Never gated on `loaded`. A preference store that will not open leaves
      // the switch at its default, which is on -
      // DiagnosticsSettings.onLoadFailed has the argument for why that
      // direction is right now that this is not consent.
      await settings.load();
      final plan = TelemetryPlan(
        dsn: dsn,
        shareLogs: settings.shareLogs,
        stamp: await BuildIdentity.resolve(),
        nativeDatabasePath: await _nativeDatabasePath(),
      );
      final why = plan.why;
      if (why != null) {
        // `caught` rather than `warn`: nothing is broken and nobody needs
        // alerting, but a dev build that was supposed to be reporting and is
        // not would otherwise be silent about it in the one place anyone
        // looks.
        LogService.caught('[Telemetry] not reporting: $why');
        return;
      }
      await _init((options) => _configure(options, plan));
      _running = true;
      _wireSinks(on: true);
      await _tag(plan);
    } catch (e, st) {
      // `error`, not `warn`: a reporting feature that failed to come up is not
      // degraded-but-fine, and the line has to survive a release build.
      LogService.error(
        '[Telemetry] init failed: ${LogService.describe(e, st)}',
      );
      // And then put it back. `Sentry.init` enables the hub *before* it runs
      // its integrations, and `_callIntegrations` has no per-integration
      // catch - so a native integration that throws leaves a live hub holding
      // the DSN. Without this, `_running` would be false, `stop()` would
      // return at its own guard, and the user would have no way to turn
      // reporting off for the rest of the session. That is the one promise §1
      // makes about that switch.
      //
      // `_tearDown` and not `stop()`: `stop()` is a transition, and a
      // transition nested inside this one ends by reconciling against the
      // value *it* was aiming at - which is false, while the switch still says
      // true. That restarted the init that had just failed, and the init
      // failed again, forever. The teardown itself is what is wanted here, not
      // the bookkeeping around it.
      _running = true;
      await _tearDown();
    } finally {
      _settling = false;
      _settleAgainIfTheSwitchMoved();
    }
  }

  /// What the transition in flight is aiming at, so a toggle during it is not
  /// lost.
  bool _settlingToward = false;

  /// Runs one more reconcile when the switch moved **during** a transition.
  ///
  /// [_reconcile] declines to act while [_settling], so without this a toggle
  /// mid-flight would be dropped - the user's last word on a privacy switch,
  /// lost to a race. Called from both transitions' `finally`.
  ///
  /// Compares the setting against [_settlingToward], the value the transition
  /// set out to reach, **not** against `_running`. The first version compared
  /// against `_running` and hung: `start()` returns early and leaves
  /// `_running` false when there is no DSN or the switch is off, so the two
  /// disagreed forever and it re-reconciled in a loop until the test timed
  /// out. Against the attempted value this fires only when the switch
  /// genuinely moved, and each run picks up the newer value - so it
  /// terminates.
  void _settleAgainIfTheSwitchMoved() {
    if (settings.shareLogs == _settlingToward) return;
    _reconcile();
  }

  /// Puts the four hooks on or takes them off, in one place.
  ///
  /// One list rather than two mirrored ones, because adding a fifth sink meant
  /// remembering two methods - and the ordering constraint below was stated in
  /// a comment on only one of them.
  ///
  /// `attachFlipperlibSink()` runs **last** either way: the level the library
  /// is pinned at is derived from whether `breadcrumbSink` is set, so
  /// re-deriving it before the assignment would leave the pin at `warning`
  /// going up, and at `info` coming down. §3.
  void _wireSinks({required bool on}) {
    guardedFailureSink = on ? _reportGuarded : null;
    LogService.keptSink = on ? _reportKept : null;
    LogService.breadcrumbSink = on ? _dropCrumb : null;
    AppHttp.exchangeSink = on ? _recordExchange : null;
    LogService.attachFlipperlibSink();
  }

  /// Shuts the SDK down, the handlers with it, and **never throws**.
  ///
  /// `Sentry.close()` also closes the native SDK, so turning the switch off
  /// stops the native crash handler and not only the Dart side - which is the
  /// whole of what §1 promises that switch does.
  Future<void> stop() async {
    if (!_running || _settling) return;
    _settling = true;
    _settlingToward = false;
    try {
      await _tearDown();
    } finally {
      _settling = false;
      _settleAgainIfTheSwitchMoved();
    }
  }

  /// Closes the SDK and takes the hooks off. **Never throws.**
  ///
  /// The body of [stop] without any of its bookkeeping, so `start()`'s own
  /// recovery can use it without starting a nested transition.
  ///
  /// `_running` is left **true** when the close fails, on purpose: the native
  /// handler may still be up, so saying otherwise would make the switch claim
  /// something that did not happen - and would make [_reconcile] refuse to try
  /// again, since it compares the setting against that flag. The user asked
  /// for reporting to stop; if it did not, that has to be visible rather than
  /// asserted.
  Future<void> _tearDown() async {
    try {
      await _shutdown();
    } catch (e, st) {
      // `_running` is left **true** on purpose. The native handler may still
      // be up, so saying otherwise would make the switch claim something that
      // did not happen - and would make `_reconcile` refuse to try again,
      // since it compares the setting against this flag. The user asked for
      // reporting to stop; if it did not, that has to be visible rather than
      // asserted.
      LogService.error(
        '[Telemetry] shutdown failed, reporting may still be running: '
        '${LogService.describe(e, st)}',
      );
      return;
    }
    _running = false;
    // And the library goes quiet again, back to the keep threshold. The cost
    // of `info` only exists while somebody is listening.
    _wireSinks(on: false);
    // The listener stays. Its lifetime is this object's - see the constructor
    // for the switch that only worked once because this used to remove it.
  }

  /// Where sentry-native keeps its crash database, or null to leave its
  /// default.
  ///
  /// Desktop only, and the default is **beside the executable** - so a
  /// `flutter run` writes `.sentry-native/` into the repository, and a shipped
  /// Windows build writes it wherever the user happened to launch from, which
  /// may not be writable.
  ///
  /// Linux is the one where the default loses data rather than merely being
  /// untidy. The launcher is self-extracting and deletes
  /// `/tmp/qunleashed-self-$$` when the process ends, so a database beside the
  /// executable goes with it - taking any crash that had not been sent yet,
  /// which on a platform with no offline cache is exactly the crash that
  /// mattered. 0013's Consequences asked where this lived; here is the answer
  /// and the fix.
  ///
  /// Carries its own catch, because `_initCore` must never throw and
  /// `getApplicationSupportDirectory` crosses a platform channel - on a
  /// platform where `path_provider` is not registered it raises
  /// `MissingPluginException`, and the headless isolate a home-screen widget
  /// starts is exactly where that has bitten before.
  static Future<String?> _nativeDatabasePath() async {
    try {
      final support = await getApplicationSupportDirectory();
      return '${support.path}/sentry-native';
    } catch (e, st) {
      LogService.caught(
        '[Telemetry] no crash database path, using the default beside the '
        'executable: ${LogService.describe(e, st)}',
      );
      return null;
    }
  }

  /// Forwards one kept log line to Sentry Logs.
  ///
  /// §2's second chokepoint. `LogService` already funnels every error and
  /// warning the app records, and §5's `caught` is the level that **will**
  /// carry the 48 failure paths a release build keeps no record of - so this
  /// is where all three arrive, rather than at several hundred call sites.
  ///
  /// Future tense on purpose: none of the 48 has moved yet.
  /// `log_level_budget_test.dart` is still at 48 and `caught_budget_test.dart`
  /// at four, all four of them new sites rather than re-ruled ones. §5's
  /// re-ruling is phase 0a and is not done.
  ///
  /// `caught` goes at Sentry's **info** level rather than `warning`, which is
  /// §5's whole point: these are searchable without firing the alerting that
  /// `warn` is for. The mapping is exhaustive over [KeptLevel] on purpose, so
  /// a fourth level cannot be added without deciding where it lands.
  ///
  /// `LogService` passes a body with absolute paths already out of it, which
  /// is all the sink does; §6.2's rest runs here, because this is the point it
  /// leaves the device.
  ///
  /// Nothing is awaited. `_emit` is synchronous and must stay that way - it is
  /// called from inside error handlers - and the SDK batches its own sends;
  /// `_guard` is what keeps a rejected send from reaching the zone as an
  /// unlabelled `[uncaught]`.
  void _reportKept(KeptLevel level, String body) {
    final text = Scrub.outbound(body);
    _guard('a kept log line was not sent', () async {
      final logger = Sentry.logger;
      await switch (level) {
        KeptLevel.error => logger.error(text),
        KeptLevel.warning => logger.warn(text),
        KeptLevel.caught => logger.info(text),
      };
    });
  }

  /// Records one finished HTTP exchange as a span.
  ///
  /// §2: hand-made, because nothing instruments `dart:io`'s `HttpClient` and
  /// the map's tile client is deliberately outside `AppHttp` - tile URLs carry
  /// the Carto key, and a span description is sent.
  ///
  /// Built after the fact with explicit timestamps, so the span is timed as if
  /// it had been opened before the request. That is what keeps `AppHttp` free
  /// of the SDK.
  ///
  /// **The query string goes.** `Scrub.outbound` would take it out anyway, but
  /// it is dropped here before the description is built, so a URL cannot
  /// arrive whole in a field the scrubber does not walk. The host and path
  /// stay: which endpoint was slow is the entire point.
  ///
  /// Nothing is recorded when there is no active transaction, which is the
  /// ordinary case for a fetch that happens before the first screen is up:
  /// `getSpan()` returns null and a span with no sampled parent would be
  /// discarded anyway.
  void _recordExchange(HttpExchange exchange) {
    final parent = Sentry.getSpan();
    if (parent == null) return;

    // `removeQuery` rather than `replace(query: '')`: Dart treats an empty
    // string as a component that is present, so that spelling leaves every
    // description ending in a dangling `?#`.
    final target = exchange.uri.removeFragment().replace(queryParameters: null);
    final span = parent.startChild(
      'http.client',
      description: Scrub.outbound('${exchange.method} $target'),
      startTimestamp: exchange.startedAt.toUtc(),
    );
    final status = exchange.status;
    if (status != null) span.setData('http.response.status_code', status);
    span.setData('http.request.method', exchange.method);
    span.throwable = exchange.error;
    _guard(
      'an HTTP span was not recorded',
      () => span.finish(
        status: _verdict(exchange),
        endTimestamp: exchange.endedAt.toUtc(),
      ),
    );
  }

  /// Whether the exchange worked, from the exchange's own answer.
  ///
  /// **`ok` outranks `status`**, which is the whole of this method. Reading the
  /// code first got two common cases backwards:
  ///
  ///  * A `304 Not Modified` is a success - `getJsonCached` serves the cached
  ///    copy and returns normally - but `SpanStatus.ok()` spans 200-299 only,
  ///    nothing in `fromHttpStatusCode`'s chain covers 300-399, and it falls
  ///    through to `unknownError()`. Every revalidated feed fetch past its TTL
  ///    was arriving in Sentry as a failed span.
  ///  * A failure *after* the headers - an idle-stall timeout, a decode
  ///    failure - has `status: 200` with an error set, because `noteStatus` runs
  ///    as soon as the response arrives and the body is read afterwards.
  ///    `fromHttpStatusCode(200)` says `ok`, so a stalled firmware download
  ///    was a successful span carrying an exception.
  ///
  /// The status code is still consulted, but only to say *how* a failure
  /// failed, and only above 400. `unknown()` and not `internalError()` for the
  /// rest: a refused connection or a DNS failure is not a claim about the
  /// server.
  static SpanStatus _verdict(HttpExchange exchange) {
    final status = exchange.status;
    if (exchange.ok) return const SpanStatus.ok();
    if (status != null && status >= 400) {
      return SpanStatus.fromHttpStatusCode(
        status,
        fallback: const SpanStatus.internalError(),
      );
    }
    return const SpanStatus.unknown();
  }

  /// Records one flipperlib line as a breadcrumb.
  ///
  /// §4: the one source of breadcrumbs, because the library's `Log.level` is
  /// a runtime check where the app's own `info` is a `const` that folds out of
  /// a release build. What this buys is the sequence in front of a crash -
  /// "link lost -> reconnecting -> reconnected" - which the app cannot produce
  /// about itself without printing everything.
  ///
  /// `category: 'flipperlib'`, so these are distinguishable in the event from
  /// whatever the SDK's own integrations add.
  ///
  /// Synchronous, unlike the other two sinks. `Sentry.addBreadcrumb` returns a
  /// future, but a breadcrumb is a write into the scope's ring buffer rather
  /// than a send - and `_guard` is still what stops a rejection reaching the
  /// zone.
  void _dropCrumb(FlipperLogLevel severity, String body) {
    final crumb = Breadcrumb(
      message: Scrub.outbound(body),
      category: 'flipperlib',
      level: _crumbLevel(severity),
    );
    _guard('a breadcrumb was not added', () => Sentry.addBreadcrumb(crumb));
  }

  /// flipperlib's five levels onto Sentry's.
  ///
  /// `debug` and `trace` collapse onto Sentry's `debug`, which is the floor
  /// worth having - and neither is reachable here anyway while the pin is
  /// `info`. Exhaustive rather than defaulted, so a sixth level in the library
  /// is a compile error here instead of an unlabelled breadcrumb.
  static SentryLevel _crumbLevel(FlipperLogLevel severity) =>
      switch (severity) {
        FlipperLogLevel.error => SentryLevel.error,
        FlipperLogLevel.warning => SentryLevel.warning,
        FlipperLogLevel.info => SentryLevel.info,
        FlipperLogLevel.debug => SentryLevel.debug,
        FlipperLogLevel.trace => SentryLevel.debug,
      };

  /// Turns one `guarded()` failure into an issue.
  ///
  /// §2: `guarded` is one of the four chokepoints that already see every
  /// failure the app records, which is why this hooks it rather than adding
  /// `captureException` to several hundred catch sites.
  ///
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
      'a guarded failure was not captured',
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
    // A transition in flight will re-check at its own end, so acting here
    // would start a second one on top of it - see [_settling].
    if (_settling) return;
    if (settings.shareLogs == _running) return;
    // `guarded` and not `unawaited`: a ChangeNotifier listener is a void
    // callback, and both of these are already no-throw - but a bare
    // `unawaited` here is the shape CLAUDE.md and #23 are about.
    _guard('following the switch failed', settings.shareLogs ? start : stop);
  }

  /// Whether a reporting failure is already being written down.
  ///
  /// `LogService._announcing` does not cover this. That flag is held around a
  /// *synchronous* call to the sink, and none of the sinks below throws
  /// synchronously - each hands its work to this method and returns, so the
  /// failure arrives a microtask later, after the flag is back to false.
  ///
  /// What that allows, without this second flag: a send rejects, the handler
  /// writes `LogService.error`, which is a kept line, which calls the kept
  /// sink, which sends, which rejects. One failure in, one failure out, for as
  /// long as the network stays broken. The only brake would be `_remember`
  /// folding an identical body - and that stops the moment any other kept
  /// line interleaves and moves `_lastKept`, which on this app means any BLE
  /// warning. CLAUDE.md names leaning on that coalescing as an anti-pattern,
  /// and termination is not something to lean on it for.
  bool _reportingAFailure = false;

  /// `guarded` without the import, which would be circular: `guarded` logs
  /// through `LogService`, and this file is what `LogService` reports
  /// *through*. Same contract - the returned future never rejects.
  ///
  /// [what] is the operation, because one message for five callers is a
  /// message that cannot say which part of reporting broke. A failed Sentry
  /// log send used to arrive in the log as a problem with the Diagnostics
  /// switch.
  void _guard(String what, Future<void> Function() task) {
    Future.sync(task).catchError((Object e, StackTrace st) {
      if (_reportingAFailure) return;
      _reportingAFailure = true;
      try {
        LogService.error('[Telemetry] $what: ${LogService.describe(e, st)}');
      } finally {
        _reportingAFailure = false;
      }
    });
  }

  /// Everything the SDK is told, in one place so §6 can be read off it.
  void _configure(SentryFlutterOptions options, TelemetryPlan plan) {
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
///
/// Returns non-null, and the type says so. `beforeSend` reads null as "drop
/// this event", which would lose exactly the failures nobody has seen
/// before - so "never drops" is worth being a fact the compiler holds rather
/// than a sentence.
/// Takes the account name out of a transaction's spans, as well as its own
/// fields.
///
/// A transaction *is* a [SentryEvent], so [scrubEvent] covers its message and
/// breadcrumbs - but not `spans`, which is where every `traced` fact and every
/// HTTP description lives. With `tracesSampleRate` at 1.0 (§8) that is a
/// sampled event class carrying free text, so §6.2 has to reach it.
///
/// `TraceScope.note` and `_recordExchange` both scrub at the source too. This
/// is the layer, not the only line: §6 is four layers for the reason the
/// section opens with, and a call site that forgets is exactly what a layer is
/// for.
SentryTransaction scrubTransaction(SentryTransaction transaction) {
  scrubEvent(transaction);
  for (final span in transaction.spans) {
    // On the context, not the span: `SentrySpan` exposes `description` only
    // through `context`, where it is mutable.
    final description = span.context.description;
    if (description != null) {
      span.context.description = Scrub.outbound(description);
    }
    _scrubStringValues(span.data);
  }
  return transaction;
}

/// Takes the account name out of one Sentry log line.
///
/// The body arrives from `_reportKept`, which has already scrubbed it. This is
/// the second line: the Logs channel does not pass through [scrubEvent] at
/// all, so without this a refactor of that one call could un-redact the
/// channel with nothing failing.
SentryLog scrubLog(SentryLog log) {
  log.body = Scrub.outbound(log.body);
  return log;
}

/// Scrubs the string values of [data] in place, leaving everything else.
///
/// Shared by the breadcrumb and span walks. A number or a bool cannot carry a
/// filename, and rewriting one into a string would change what the event
/// means.
void _scrubStringValues(Map<String, dynamic>? data) {
  if (data == null) return;
  for (final key in data.keys) {
    final value = data[key];
    if (value is String) data[key] = Scrub.outbound(value);
  }
}

SentryEvent scrubEvent(SentryEvent event) {
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
    _scrubStringValues(crumb.data);
  }

  return event;
}
