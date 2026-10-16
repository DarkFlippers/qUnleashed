import 'package:flipperlib/flipperlib.dart'
    show FlipperConnectErrorKind, FlipperLogLevel;
import 'package:flutter/widgets.dart' show NavigatorObserver, Widget;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../build_identity.dart';
import '../connection/connect_report.dart';
import '../guarded.dart';
import '../http/app_http.dart';
import '../logging.dart';
import 'options.dart';
import 'plan.dart';
import 'scrub.dart';
import 'settings.dart';

/// The one place in `lib/` that imports the Sentry SDK.
///
/// [ADR 0013 §2](../../../docs/adr/0013-observability-with-sentry.md) makes
/// this folder the boundary and `test/sentry_import_guard_test.dart` holds it.
/// Everything above keeps calling `LogService`, `guarded` and the connection
/// classifier; this turns what they already record into events.
///
/// Phases 1 and 2 of the rollout - errors, crashes, Sentry Logs, breadcrumbs
/// and tracing - and phase 3 apart from §3's flipperlib observer: replay with
/// `onErrorSampleRate` behind §1's
/// second switch, `sessionSampleRate` at zero and §6.4's gate opened with four
/// masking rules rather than stepped over, plus the one metric §2 asks for in
/// [_reportConnectFailure].
///
/// This paragraph has now said the opposite twice, each time because a phase
/// landed and made it false.
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

  /// What the running SDK was told about replay, which is not the same thing
  /// as what the switch says now.
  ///
  /// The sample rates are read once, by `SentryFlutter.init`, and 9.30.1 has
  /// no pause API - so a replay switch that moved while the SDK is up can only
  /// be applied by taking it down and bringing it back. [_reconcile] compares
  /// against this to know whether that is needed, exactly as it compares
  /// `shareLogs` against [_running].
  ///
  /// **Written wherever [_running] is written**, including `start()`'s own
  /// recovery. Left behind there once, and a stale value here is not a cosmetic
  /// problem: it is a standing disagreement with the switch, which is what
  /// [_replayRestartAimedAt] exists to keep from becoming a loop.
  bool _runningWithReplay = false;

  /// The value the last replay restart set out to apply, or null if none is
  /// outstanding.
  ///
  /// This is a termination guard, not bookkeeping. Applying a replay change
  /// means calling [stop] while the main switch still says on, and `_tearDown`
  /// deliberately leaves [_running] true when the shutdown fails - so that
  /// `_reconcile` can be asked again rather than claiming something that did
  /// not happen. Those two decisions are each right and together they did not
  /// terminate: the failed stop left the same disagreement in place, and
  /// `stop`'s own `finally` reconciled straight back into it.
  ///
  /// That is not a spin. Each cycle is synchronous work plus a microtask, so
  /// the event queue is never reached, no timer ever fires - a test's own
  /// `Timeout` cannot fire either - and the UI isolate is wedged for good. On
  /// Windows and Linux every cycle also pays the synchronous
  /// `sentry_close()` described on [_batchedSinceStart].
  ///
  /// So a restart is attempted once per value. The latch is dropped as soon as
  /// the switch and [_runningWithReplay] agree, which is both what a successful
  /// restart produces and what toggling back to the running value produces, so
  /// a later genuine change is still applied. `start()`'s recovery leaving
  /// `_runningWithReplay` stale is how this used to be reached without the
  /// user touching the switch twice; the same shape, with the same ending, is
  /// written down at that `catch`.
  bool? _replayRestartAimedAt;

  /// What the transition in flight was told about replay.
  ///
  /// The replay half of [_settlingToward], and it earns its keep in the same
  /// place: a tap during a transition would otherwise be dropped, because the
  /// plan that transition is using was built before it. The logs switch went
  /// to this trouble already; this is the more sensitive of the two switches.
  bool _settlingTowardReplay = false;

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

  /// Wraps the app so the recorder can see the tree it is recording.
  ///
  /// `SentryWidget` mounts `SentryScreenshotWidget`, and replay captures
  /// through it: without it `ScreenshotRecorder.capture` finds no render
  /// object and skips every frame, warning "SentryScreenshotWidget is not
  /// attached" once per recorder and then recording nothing in silence. The
  /// warning goes through `internalLogger`, which `options.dart` gates on
  /// `LogService.printing` - so in a quiet build there is no line at all,
  /// only the silence. So this is not optional decoration around `runApp`.
  ///
  /// **`SentryScreenshotWidget` and not `SentryWidget`**, which every example
  /// reaches for. `SentryWidget` mounts `SentryUserInteractionWidget` as well,
  /// and that is what `enableUserInteractionBreadcrumbs` and
  /// `enableUserInteractionTracing` need - both default true, so the obvious
  /// wrapper would also have switched on a second breadcrumb source §4 does
  /// not have, and a `ui.action.click` transaction per tap at
  /// `tracesSampleRate: 1.0`. The breadcrumb carries a ten-deep list of
  /// ancestor labels, and `scrubEvent` rewrites top-level strings only, so
  /// `/ext` paths and file names in a `ValueKey` would have left unscrubbed.
  /// `options.dart` pins both flags off so a later swap back to `SentryWidget`
  /// fails a diff rather than reopening that quietly.
  ///
  /// [child] comes back untouched in a build with no DSN, which is every local
  /// build by default - so an app nobody reports from carries no wrapper, the
  /// same promise [navigatorObservers] makes about the observer.
  ///
  /// Returns a Flutter type and takes one, so `main.dart` and `app.dart` stay
  /// free of the SDK. §2.
  Widget wrap(Widget child) =>
      configured ? SentryScreenshotWidget(child: child) : child;

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
    if (_running || _settling || _closedForExit) return;
    _settling = true;
    _settlingToward = true;
    _settlingTowardReplay = settings.shareReplay;
    try {
      // Never gated on `loaded`. A preference store that will not open leaves
      // the switch at its default, which is on -
      // DiagnosticsSettings.onLoadFailed has the argument for why that
      // direction is right now that this is not consent.
      await settings.load();
      final plan = TelemetryPlan(
        dsn: dsn,
        shareLogs: settings.shareLogs,
        shareReplay: settings.shareReplay,
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
      await _init((options) => configureOptions(options, plan));
      _running = true;
      _runningWithReplay = plan.shareReplay;
      _replayRestartAimedAt = null;
      _wireSinks(on: true);
      await tagScope(plan);
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
      // Paired with `_running`, and the pairing is the point. The plan is out
      // of scope here, but `_settlingTowardReplay` holds what this transition
      // set out to apply, which is what a half-up SDK was configured with.
      // Leaving the old value stood as a disagreement with the switch that
      // nothing had asked for, and `_reconcile`'s replay arm would act on it
      // at the next `notifyListeners()` - including the one a retried
      // `settings.load()` sends. See [_replayRestartAimedAt].
      _runningWithReplay = _settlingTowardReplay;
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
    if (settings.shareLogs != _settlingToward) {
      _reconcile();
      return;
    }
    // The logs switch ended where this transition aimed, and the replay one
    // may not have. Only worth asking while sharing is on: with it off nothing
    // is running for a replay to be attached to.
    if (settings.shareLogs && settings.shareReplay != _settlingTowardReplay) {
      _reconcile();
    }
  }

  /// Puts the five hooks on or takes them off, in one place.
  ///
  /// One list rather than two mirrored ones, because adding a sink meant
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
    connectFailureSink = on ? _reportConnectFailure : null;
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
    _settlingTowardReplay = settings.shareReplay;
    try {
      await _tearDown();
    } finally {
      _settling = false;
      _settleAgainIfTheSwitchMoved();
    }
  }

  /// Whether [closeForExit] has run. One-way, for the reason it gives.
  bool _closedForExit = false;

  /// Drains what is buffered, closes the SDK, and does not let it come back.
  ///
  /// For a process that is ending. [stop] is what the Diagnostics switch
  /// calls and it is the wrong thing here: its `finally` reconciles against
  /// that switch, which is still **on** - so a stop nobody asked for is
  /// followed immediately by a fresh `SentryFlutter.init`, native layer
  /// included, racing the window's own destruction. The first version of
  /// `AppShutdown`'s flush called `stop()` and did exactly that.
  ///
  /// The latch is what makes it one-way, and it is the point rather than
  /// bookkeeping. [_reconcile] is where it earns its keep: a successful close
  /// leaves `_running` false against a switch that still says on, which is
  /// exactly the disagreement that listener acts on. The check in [start] is
  /// for a caller that does not exist yet - today's two are `_initCore`, long
  /// before any window hook, and that listener. Nothing clears it, because
  /// nothing left in this process should want to.
  ///
  /// Two things it does **not** cover, both milliseconds wide on a process
  /// that is ending. A quit while `start()` is still inside `settings.load()`
  /// finds `_running` false and drains nothing - there is nothing buffered
  /// that early either. And unlike [stop] this does not stand off for
  /// `_settling`: a transition that has already passed `_init` can finish
  /// behind this and leave the SDK up for the rest of the exit. The latch
  /// means nothing starts a *new* one.
  Future<void> closeForExit() async {
    _closedForExit = true;
    if (!_running || !_batchedSinceStart) return;
    await _tearDown();
  }

  /// Whether anything the SDK batches has been handed to it since it came up.
  ///
  /// The gate on [closeForExit], and not a micro-optimisation: on Windows and
  /// Linux `NativeSdkIntegration.close()` is a **synchronous** FFI call into
  /// `sentry_close()`, which flushes and joins sentry-native's transport
  /// worker under its own two-second shutdown timeout. A synchronous call
  /// cannot be interrupted by `Future.timeout` - the timer cannot even fire
  /// while it runs - so the caller's budget does not bound it. Paying that on
  /// every quit to drain a batcher that is provably empty is the wrong trade,
  /// and skipping it leaves the exit exactly as it was before the flush
  /// existed.
  ///
  /// Kept lines and metrics are what can be waiting. Both go through the SDK's
  /// one `TelemetryProcessor` and then into a buffer each - `logBuffer` and
  /// `metricBuffer` are separate, with their own counters and their own
  /// timer - and each holds its items until 100 of them, a megabyte, or five
  /// seconds (9.30.1, unchanged in 10.0.0-rc.1). `close()` flushes both, which
  /// is why one flag over the two is enough. Transactions are not batched
  /// (`traceLifecycle` is `static`, so `finish` sends), breadcrumbs ride on
  /// the next event, and an issue queues its own send.
  ///
  /// A connect that failed as the user quit is the one this would otherwise
  /// have lost.
  bool _batchedSinceStart = false;

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
      // The recorder's hook does not come off with the SDK. `ReplayIntegration`
      // registers an `onBuild` callback into a **static** list on
      // `SentryScreenshotWidget` and never unregisters - it does not override
      // `close()` - and while `SentryFlutter.init` clears that list (so the
      // replay switch's restart does not accumulate hooks), `Sentry.close()`
      // does not. Left alone, turning sharing off keeps the dead options graph
      // alive for the process - the DSN, every masking rule, all three
      // `beforeSend` closures - and fires `setReplayConfig` at a closed SDK
      // once per rotation. Nothing leaves the device, but holding the DSN and
      // the privacy rules after the user said no is the wrong thing to keep.
      //
      // Only on the success path: a shutdown that failed may leave the native
      // recorder up, and taking its hook off would then be the lie this
      // method's `_running` handling is careful not to tell.
      // ignore: invalid_use_of_internal_member
      SentryScreenshotWidget.reset();
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
  /// The body arrives raw - `LogService` deliberately does not scrub, so the
  /// console keeps the real path - so `Scrub.outbound` here is the *whole* of
  /// §6.2 for this channel, starting with the absolute paths, and this is the
  /// point it leaves the device.
  ///
  /// Nothing is awaited. `_emit` is synchronous and must stay that way - it is
  /// called from inside error handlers - and the SDK batches its own sends;
  /// `_guard` is what keeps a rejected send from reaching the zone as an
  /// unlabelled `[uncaught]`.
  void _reportKept(KeptLevel level, String body) {
    // One of the two things that can leave something in the SDK's buffers, so
    // one of the two that make the exit flush worth paying for - §2's connect
    // counter is the other. See [closeForExit].
    _batchedSinceStart = true;
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

    // Rebuilt from components, because neither spelling of "take the query
    // off" actually does it. `replace(queryParameters: null)` reads null as
    // *keep this component* and hands the query back intact - the version that
    // stood here, which left `?key=…` in the target and leaned entirely on
    // `Scrub.outbound` below. `replace(query: '')` does drop it, but leaves a
    // dangling `?`, because Dart treats the empty string as a component that
    // is present. All three spellings were run to check.
    //
    // Belt and braces on purpose: `Scrub.outbound` strips the query as well,
    // and this is the layer that keeps a regression there from being a leak on
    // its own.
    final source = exchange.uri;
    final target = Uri(
      scheme: source.scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: source.path,
    );
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

  /// Turns one classified connect failure into a count, or into an issue.
  ///
  /// §2's `classifyConnectError` row, and the metrics half of phase 3. The
  /// kinds the classifier knows are a counter and a breadcrumb: nobody needs
  /// an issue per Bluetooth-is-off, and what is worth knowing about them is a
  /// shape - which kinds users actually hit, on which transport, and whether
  /// the app dialled or they did. `unknown` over BLE is the opposite and goes
  /// to [_reportUnknownConnect]: one issue per platform string the classifier
  /// has not learned yet, each of them a sentence shown to a user that was
  /// wrong.
  ///
  /// **`unknown` over USB is counted, not raised**, which amends §2's row and
  /// is the one place this departs from it. The classifier's needles were
  /// written against BLE stacks, and the ones that are generic enough to catch
  /// a USB failure - `timeout`, `not found`, `disconnected`, `unauthorized` -
  /// file it under a kind named for Bluetooth; what is left matches nothing.
  /// So an issue per unmatched USB string would be an issue per replug, since
  /// `LinkService._autoTriedUsb` re-arms on one, in the list §2 keeps for
  /// strings the classifier can *learn* - and there is nothing to learn into:
  /// USB needles are a flipperlib change, not a line here. The volume shape is
  /// the one that has already cost this project real errors. They stay a
  /// counter, at `kind: unknown`, and a kept log line at the call site.
  ///
  /// Nothing is awaited, like the sinks above - and here the SDK does not even
  /// offer the choice: `Sentry.metrics.count` returns void and unawaits its own
  /// capture internally. So `_guard` covers a synchronous throw out of the
  /// hub, not a failed send; a dropped metric is reported by Sentry's own
  /// client reports rather than by this app.
  void _reportConnectFailure(
    FlipperConnectErrorKind kind,
    Object error,
    StackTrace stack, {
    required ConnectAttempt attempt,
    required bool isBle,
  }) {
    final transport = transportLabel(isBle);
    if (kind == FlipperConnectErrorKind.unknown && isBle) {
      _reportUnknownConnect(error, stack, attempt: attempt);
      return;
    }

    _batchedSinceStart = true;
    _guard(
      'a connect failure was not counted',
      () async => Sentry.metrics.count(
        'device.connect.failed',
        1,
        attributes: {
          'kind': SentryAttribute.string(kind.name),
          'transport': SentryAttribute.string(transport),
          'attempt': SentryAttribute.string(attempt.name),
        },
      ),
    );

    // `category: 'connection'` rather than `'flipperlib'`, so §4's timeline
    // and this are distinguishable in an event that carries both - and not
    // through `_dropCrumb`, which is the library's sink and would label it as
    // if the library had said it.
    //
    // Unscrubbed on purpose, and the only sink here that can say so: every
    // part of this message is one of the three closed vocabularies above.
    // Nothing from the device, the file system or the thrown object reaches
    // it - the thrown object's own text is already a kept log line.
    _guard(
      'a connect breadcrumb was not added',
      () => Sentry.addBreadcrumb(
        Breadcrumb(
          message:
              'connect failed: ${kind.name} on $transport (${attempt.name})',
          category: 'connection',
          level: SentryLevel.warning,
        ),
      ),
    );
  }

  /// The one connect failure that becomes an issue: a string nothing knows.
  ///
  /// §2 asks for this list by name, and the grouping is the whole of the
  /// request. Sentry's default groups on the stack, which here says which of
  /// the handful of catch sites saw the failure rather than what the platform
  /// said - so one string arriving from two sites would be two issues, and two
  /// strings from one site one. The fingerprint therefore carries the message,
  /// which is the field grouping usually treats as noise and is here the
  /// entire finding.
  ///
  /// BLE only, for the reason [_reportConnectFailure] gives about USB.
  ///
  /// [_connectSignature] is what keeps that from going the other way. The
  /// message holds a BLE address or a serial often enough, and without it the
  /// same unseen string from two Flippers is two issues - a list of devices
  /// where §2 asked for a list of strings.
  ///
  /// The message is scrubbed before it reaches either the fingerprint or the
  /// context, because `scrubEvent` walks neither. Built inside the guard, so
  /// an object whose `toString()` throws - which `guarded` documents as real -
  /// is one unreported error rather than a throw inside a `catch` block.
  void _reportUnknownConnect(
    Object error,
    StackTrace stack, {
    required ConnectAttempt attempt,
  }) {
    _guard('an unclassified connect error was not captured', () {
      final message = Scrub.outbound('$error');
      return Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          scope.fingerprint = [
            'device.connect',
            error.runtimeType.toString(),
            _connectSignature(message),
          ];
          scope.setContexts('connect', {
            'kind': FlipperConnectErrorKind.unknown.name,
            // Constant, because the one caller is the BLE arm.
            'transport': transportLabel(true),
            'attempt': attempt.name,
            'message': message,
          });
        },
      );
    });
  }

  /// What makes two unclassified connect errors the same issue.
  ///
  /// Identifiers out, error codes left in, and the asymmetry is the point: a
  /// BLE address, a serial or an iOS peripheral identifier varies per device
  /// and per pairing and says nothing about the cause, while a code usually
  /// *is* the cause - Android's `status 133` and `status 22` are different
  /// failures and must not merge into one issue. A *service* UUID is a
  /// constant and identical on every Flipper; it is the peripheral identifier
  /// CoreBluetooth hands out instead of a MAC that varies, and it is why the
  /// UUID rule is here at all.
  ///
  /// **Where the line falls is twelve characters, and it was eight.** Eight
  /// took `0x80070005` and `0x8007048F` down to one `0x<id>` - two different
  /// Windows HRESULTs, which `universal_ble`'s Windows plugin produces by
  /// stringifying `hresult_error::code()`. Two causes in one issue, titled
  /// after whichever arrived first, and the second never learned: the exact
  /// inversion of what this is for. The case below it could not see that,
  /// because `133` and `22` are too short to reach the boundary either way.
  /// Twelve loses nothing the rule is for - a separator-less BLE address is
  /// twelve hex characters and a serial is longer.
  static String _connectSignature(String message) =>
      message.replaceAll(_identifier, '<id>');

  static final RegExp _identifier = RegExp(
    // A MAC or a BLE address: four or more colon-separated pairs, so a clock
    // or a timeout written `12:30` in a message is left alone.
    r'[0-9a-f]{2}(?::[0-9a-f]{2}){3,}'
    // A UUID. Its position used to be load-bearing - at eight characters the
    // bare-run rule below took its first group and left the rest - and at
    // twelve it is not, because a UUID's leading group is eight hex and then a
    // hyphen.
    r'|[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}'
    // A separator-less address, a serial, a handle: twelve hex characters or
    // more. Not eight - the boundary paragraph above is why.
    r'|[0-9a-f]{12,}',
    caseSensitive: false,
  );

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
    // And nothing comes back up once the process is on its way out, whatever
    // the switch says - see [closeForExit].
    if (_closedForExit) return;
    if (settings.shareLogs == _running) {
      // The main switch agrees with reality. The replay one may not, and the
      // rates are read once at `init` with no pause API in this major - so
      // the only way to apply it is to bring the SDK down.
      //
      // `stop` and not a restart of its own: stopping leaves `_running` false
      // against a switch that still says on, which is the disagreement this
      // very listener acts on - `_tearDown` ends by reconciling and `start`
      // runs again with a plan built from the new value. That implicit second
      // half is load-bearing rather than incidental, which is why
      // `test/telemetry_lifecycle_test.dart` asserts the SDK comes back up
      // carrying the new rate rather than merely that it went down.
      //
      // Not where replay cannot run at all. `NativeSdkIntegration.close` is a
      // synchronous FFI `sentry_close()` on the desktop targets, which
      // `_batchedSinceStart` already documents as uninterruptible under its
      // two-second timeout - so restarting for a rate no recorder will read
      // would freeze the UI isolate with the crash handler down, in exchange
      // for nothing. The Diagnostics row is hidden there for the same reason.
      //
      // And at most once per value, which [_replayRestartAimedAt] is the whole
      // explanation of: without it a shutdown that fails reconciles straight
      // back into this branch and never leaves it.
      if (settings.shareReplay == _runningWithReplay) {
        // In agreement, so any outstanding attempt is spent - whether it
        // succeeded or the user put the switch back where it was.
        _replayRestartAimedAt = null;
      } else if (_running &&
          DiagnosticsSettings.replaySupported &&
          settings.shareReplay != _replayRestartAimedAt) {
        _replayRestartAimedAt = settings.shareReplay;
        // The restart is a reporting blackout: all five sinks come off and the
        // native handler goes down for a native close plus a native init, a
        // `BuildIdentity.resolve()` and a platform channel. A crash lost in
        // that window is indistinguishable from no crash, so the gap is named
        // here and shows up in the timeline of the next report.
        LogService.caught(
          '[Telemetry] restarting to apply the replay switch; nothing is '
          'reported until it is back up',
        );
        _guard('following the replay switch failed', stop);
      }
      return;
    }
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
  /// long as the network stays broken. The only brake would be the fold
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
}
