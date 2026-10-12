// `Telemetry.start`, `stop` and the switch that drives them — ADR 0013 §1.
//
// None of this could run before. `QU_SENTRY_DSN` is a `String.fromEnvironment`
// and no `--dart-define` reaches `flutter test`, so `TelemetryPlan.enabled`
// was false in every run and `start()` returned at its own guard. Three
// blocking bugs shipped in that blind spot and a review found all three:
//
//  * the `_reconcile` listener went on inside `start()`'s success block and
//    came off in `stop()`, which made the switch one-way, once, per process -
//    the §1 notice's **Turn it off** removed it, so turning it back on did
//    nothing;
//  * a `start()` that threw after `Sentry.init` left a live hub with
//    `_running == false`, so `stop()` refused to run and reporting could not
//    be turned off at all;
//  * a `stop()` whose close failed set `_running = false` anyway, so the
//    switch said off while the native handler was still up.
//
// The DSN, the init and the shutdown are injected for exactly this.
import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/http/app_http.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/services/telemetry/telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'quiet_log.dart';
import 'telemetry_sinks.dart';

/// Which seam each case reads, and why they are not all the same one.
///
/// This file is the one that owns `LogService.keptSink`, so the recorder in
/// `kept_lines.dart` fights it in two ways:
///
///  * [anySinkInstalled] asserts on whether the hook is set *at all*, and a
///    recorder sitting in it would make "nothing was installed" unobservable -
///    which is exactly what the no-DSN and switch-off cases must show. Hence
///    [keptRecorder]: the predicates below discount it, so the recorder can
///    stay installed and still be told apart from a sink `Telemetry` wired.
///  * `Telemetry.stop()` clears all four hooks, so by the time a failed close
///    is logged the recorder is gone. That one case reads the console, and
///    [onConsole] is there so it does not silently become vacuous if this file
///    is ever added to CI's quiet job.
///
/// Everything else reads the recorder, deliberately: `caught` and `error` are
/// kept in a build that prints nothing, which is the whole of §5, and an
/// assertion that went through the console instead would be build-dependent
/// for no reason.
int get onConsole => LogService.printing ? 1 : 0;

/// A stand-in for the SDK's own lifecycle.
class _FakeSdk {
  int inits = 0;
  int closes = 0;

  /// Thrown by [init] when set, to drive the half-initialised state.
  Object? initThrows;

  /// Thrown by [close] when set.
  Object? closeThrows;

  /// How many closes [closeThrows] applies to, after which [close] succeeds.
  ///
  /// A safety valve, and the reason it exists is worth stating: a missing
  /// termination guard on the replay restart does not spin, it starves the
  /// event queue, so no timer fires and a test's own `Timeout` cannot fire
  /// either - the run wedges for good and takes CI with it. Letting the close
  /// succeed eventually breaks any loop, so the regression arrives as a
  /// failed count instead of a hang.
  int closeThrowsLimit = 1 << 30;

  /// The replay error rate each [init] was given, in order.
  ///
  /// A count of inits cannot tell a restart carrying a new rate from a second
  /// init carrying the old one, and that difference is the whole of the replay
  /// switch.
  final rates = <double?>[];

  /// The options the configure callback produced, so the block is checkable.
  SentryFlutterOptions? options;

  Future<void> init(void Function(SentryFlutterOptions) configure) async {
    inits += 1;
    final built = SentryFlutterOptions();
    configure(built);
    options = built;
    rates.add(built.replay.onErrorSampleRate);
    final boom = initThrows;
    if (boom != null) throw boom;
  }

  Future<void> close() async {
    closes += 1;
    final boom = closeThrows;
    if (boom != null && closes <= closeThrowsLimit) throw boom;
  }
}

/// Whether `Telemetry` has a kept-log sink in place.
///
/// Discounts the test's own recorder, which `recordKeptLines` leaves in the
/// same static. Without this every "nothing was installed" assertion below
/// would be reading the recorder and passing on it.
bool get telemetryKeptSinkInstalled =>
    LogService.keptSink != null && LogService.keptSink != keptRecorder;

/// Whether any of the four hooks is installed.
bool get anySinkInstalled =>
    guardedFailureSink != null ||
    telemetryKeptSinkInstalled ||
    LogService.breadcrumbSink != null ||
    AppHttp.exchangeSink != null;

/// The masking rules the options block added, §6.4's gate, as
/// `'<type>: <decision>'`.
///
/// Public API throughout: `privacy` and `privacy.toJson()` are both
/// unannotated, and `toJson` emits `'${rule.name}: ${rule.description}'`.
/// `options.dart` passes no `description`, so the SDK fills it with the
/// literal `'mask'` or `'unmask'` and the decision lands in the string. These
/// therefore read `HexTable: mask`.
///
/// **That is the whole point of reading it this way.** The earlier version of
/// this helper mapped `userMaskingRules` to `rule.name` behind an
/// `invalid_use_of_internal_member` ignore, and `mask<T>()` and `unmask<T>()`
/// both append a rule named `T.toString()` - so `mask` -> `unmask` passed
/// every case in this file, including the one named for these masks. It was
/// not a hypothetical: a reviewer made that edit and the suite went green.
/// `unmask` is the worst possible failure here, because it applies to the
/// subtree and short-circuits later rules, so it also defeats `maskAllText`
/// inside the hex table.
///
/// The honest limit is now one step further out: this asserts the decision the
/// options block recorded, not what the SDK does with it. A change in how a
/// constant rule is applied would pass. Covering that means building a
/// `HexTable`, a `RemoteScreen` and a `PlotterView`, each wanting five
/// collaborators, in a test about telemetry - and §6.4 still owes a check on a
/// device either way.
Iterable<String> maskedTypes(SentryFlutterOptions options) =>
    (options.privacy.toJson()['maskingRules'] as List<dynamic>? ??
            const <dynamic>[])
        .cast<String>();

/// Whether all four are.
bool get allSinksInstalled =>
    guardedFailureSink != null &&
    telemetryKeptSinkInstalled &&
    LogService.breadcrumbSink != null &&
    AppHttp.exchangeSink != null;

void main() {
  setUp(recordKeptLines);

  // `DiagnosticsSettings.replaySupported` is false on the host, and the
  // replay restart is gated on it - so without this every case below would
  // pass by never reaching the code it names.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  late _FakeSdk sdk;
  late DiagnosticsSettings settings;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sdk = _FakeSdk();
    settings = DiagnosticsSettings();
  });

  tearDown(resetTelemetrySinks);

  Telemetry build({String dsn = 'https://key@o1.ingest.de.sentry.io/2'}) =>
      Telemetry(
        settings: settings,
        dsn: dsn,
        init: sdk.init,
        shutdown: sdk.close,
      );

  group('coming up', () {
    test('installs all four hooks and raises the library pin', () async {
      // The pin is derived from whether `breadcrumbSink` is set, and
      // `attachFlipperlibSink()` has to run after the assignment. Swap the two
      // and §4's whole breadcrumb timeline is silently empty - nothing else
      // would fail.
      final telemetry = build();
      await telemetry.start();

      expect(telemetry.running, isTrue);
      expect(allSinksInstalled, isTrue);
      if (!LogService.printing) {
        expect(Log.level, FlipperLogLevel.info);
      }
    });

    test('is idempotent', () async {
      final telemetry = build();
      await telemetry.start();
      await telemetry.start();
      expect(sdk.inits, 1);
    });

    test('a build with no DSN installs nothing and says why once', () async {
      final telemetry = build(dsn: '');
      await quietlyAsync(telemetry.start);

      expect(sdk.inits, 0);
      expect(telemetry.running, isFalse);
      expect(anySinkInstalled, isFalse);
      expect(keptLines.where((l) => l.contains('no DSN')), hasLength(1));
    });

    test('the switch being off installs nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_logs': false,
      });
      final telemetry = build();
      await quietlyAsync(telemetry.start);

      expect(sdk.inits, 0);
      expect(anySinkInstalled, isFalse);
      expect(keptLines.where((l) => l.contains('Settings')), hasLength(1));
    });

    test('§6 and §8 reach the options', () async {
      // The options block is where the privacy decisions live, and a test is
      // the only thing that notices if one is dropped.
      await build().start();
      final options = sdk.options!;

      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.enablePrintBreadcrumbs, isFalse);
      expect(options.tracesSampleRate, 1.0);
      expect(options.enableLogs, isTrue);
      expect(options.enableFramesTracking, isFalse);
      // All three scrubbing hooks, not just the one. A log never passes
      // through `beforeSend`, and a transaction only reaches it when
      // `beforeSendTransaction` is unset.
      expect(options.beforeSend, isNotNull);
      expect(options.beforeSendTransaction, isNotNull);
      expect(options.beforeSendLog, isNotNull);
    });

    test('records a replay for an error and never a session', () async {
      await build().start();
      final replay = sdk.options!.replay;

      expect(replay.onErrorSampleRate, 1.0);
      // Zero, and not pending a decision: continuous recording feeds the same
      // envelope cache that was measured dropping error events under load.
      expect(replay.sessionSampleRate, anyOf(isNull, 0.0));
    });

    test('masks the three surfaces §6.4 names, and masks rather than '
        'unmasks them', () async {
      // The gate itself. Both defaults are on and neither reaches these: the
      // hex editor paints card bytes with a `TextPainter` inside a
      // `CustomPainter`, so it is not a `Text`, and the remote screen is a
      // `RawImage`, so it is not an `Image`. Without the two rules, switching
      // replay on records every card dump and the live device screen.
      await build().start();
      final options = sdk.options!;

      expect(options.privacy.maskAllText, isTrue);
      expect(options.privacy.maskAllImages, isTrue);
      expect(
        maskedTypes(options),
        containsAll([
          'HexTable: mask',
          'RemoteScreen: mask',
          'PlotterView: mask',
        ]),
      );
    });

    test('the replay switch off leaves the error rate at zero', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_replay': false,
      });

      await build().start();

      expect(sdk.options!.replay.onErrorSampleRate, 0.0);
      // And the rest of reporting is untouched: §1's second switch is one
      // signal fewer, not a reason to send nothing.
      expect(sdk.options!.dsn, isNotNull);
      expect(allSinksInstalled, isTrue);
    });

    test('masks the three surfaces even with replay switched off', () async {
      // The rules do not depend on the rate, and should not: the switch can
      // move while the app runs, and a rule added only on the recording path
      // would be the one missing from the build that starts recording.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_replay': false,
      });

      await build().start();

      expect(
        maskedTypes(sdk.options!),
        containsAll([
          'HexTable: mask',
          'RemoteScreen: mask',
          'PlotterView: mask',
        ]),
      );
    });
  });

  group('an init that fails part way', () {
    test('closes the hub rather than leaving it up and unstoppable', () async {
      // `Sentry.init` enables the hub before running its integrations and
      // `_callIntegrations` has no per-integration catch, so a throw here
      // means a live hub. Leaving `_running` false would make `stop()` refuse
      // and the user could not turn reporting off for the session.
      sdk.initThrows = StateError('native integration refused');
      final telemetry = build();

      await quietlyAsync(telemetry.start);

      expect(telemetry.running, isFalse);
      expect(sdk.closes, 1, reason: 'the live hub was closed');
      expect(anySinkInstalled, isFalse);
      expect(
        keptLines.where((l) => l.contains('[Telemetry] init failed')),
        hasLength(1),
        reason: 'and `_tearDown` put the recorder back before this was logged',
      );
    });

    test('never throws, because _initCore awaits it unguarded', () async {
      sdk.initThrows = StateError('nope');
      await expectLater(build().start(), completes);
    });
  });

  group('going down', () {
    test('clears all four hooks and lowers the pin', () async {
      final telemetry = build();
      await telemetry.start();

      await telemetry.stop();

      expect(telemetry.running, isFalse);
      expect(anySinkInstalled, isFalse);
      if (!LogService.printing) {
        expect(Log.level, FlipperLogLevel.warning);
      }
    });

    test(
      'a close that fails keeps running true, so the switch cannot lie',
      () async {
        // The native handler may still be up. Saying otherwise would make the
        // switch claim something that did not happen, and would make
        // `_reconcile` refuse to try again.
        final telemetry = build();
        await telemetry.start();
        sdk.closeThrows = StateError('close refused');

        // The console, and the only case that needs it: `stop()` clears all
        // four hooks before this is logged, so the recorder is not there to
        // hear it. `onConsole` rather than 1 so a quiet build reads as "not
        // observable here" instead of silently asserting nothing.
        final lines = await printedAsync(telemetry.stop);

        expect(telemetry.running, isTrue);
        expect(
          lines.where((l) => l.contains('may still be running')),
          hasLength(onConsole),
        );
      },
    );

    test('never throws', () async {
      final telemetry = build();
      await telemetry.start();
      sdk.closeThrows = StateError('nope');
      await expectLater(telemetry.stop(), completes);
    });
  });

  group('wrap', () {
    // The whole of what makes replay capture anything, and it had no test.
    //
    // Everything else in this feature fails loudly when it breaks: a dropped
    // mask fails a case below, a renamed widget fails to compile. This one
    // fails silently in both directions - without the wrapper
    // `ScreenshotRecorder.capture` finds no render object and records nothing
    // for the life of the process, and the SDK's own warning about that is
    // compiled out of release builds by `RuntimeChecker.kDebugMode`. So the
    // switch would say replay is on and nothing would ever be recorded, with
    // no line anywhere.
    test('puts the recorder above the app when there is a DSN', () {
      const child = SizedBox.shrink();
      final wrapped = build().wrap(child);

      expect(wrapped, isA<SentryScreenshotWidget>());
      expect((wrapped as SentryScreenshotWidget).child, same(child));
    });

    test('is SentryScreenshotWidget and not SentryWidget', () {
      // `SentryWidget` is what every SDK example reaches for, and it also
      // mounts `SentryUserInteractionWidget` - which turns on a breadcrumb
      // carrying ten ancestors' labels past a scrubber that only rewrites
      // top-level strings, and a transaction per tap at `tracesSampleRate`
      // 1.0. `options.dart` pins both flags off; this is the other half of
      // that, and it is a one-word edit away from being undone.
      expect(build().wrap(const SizedBox.shrink()), isNot(isA<SentryWidget>()));
    });

    test('hands the app back untouched with no DSN', () {
      // The same promise `navigatorObservers` makes: a build nobody reports
      // from carries no wrapper at all.
      const child = SizedBox.shrink();
      final Widget wrapped = build(dsn: '').wrap(child);

      expect(wrapped, same(child));
    });
  });

  group('the switch', () {
    test('turning it off stops the SDK', () async {
      final telemetry = build();
      await telemetry.start();

      await settings.setShareLogs(false);
      await pumpEventQueue();

      expect(telemetry.running, isFalse);
      expect(sdk.closes, 1);
      expect(anySinkInstalled, isFalse);
    });

    test('and turning it back on starts it again', () async {
      // The bug this file exists for. The listener used to come off in
      // `stop()`, so this second toggle reached nobody: the row showed on, the
      // preference persisted as on, and nothing reported until a restart.
      final telemetry = build();
      await telemetry.start();
      await settings.setShareLogs(false);
      await pumpEventQueue();

      await settings.setShareLogs(true);
      await pumpEventQueue();

      expect(telemetry.running, isTrue);
      expect(sdk.inits, 2);
      expect(allSinksInstalled, isTrue);
    });

    test('the replay switch brings the SDK back up with the new rate', () async {
      // There is no pause API in 9.30.1: the rates are read once, by `init`.
      // So `_reconcile` applies a replay change by calling `stop`, and the
      // main switch - still on - is what brings it back through
      // `_settleAgainIfTheSwitchMoved`. That second half is implicit, which is
      // why it is asserted here rather than trusted: a reading of the code
      // that stops at `stop` would conclude this turns reporting off.
      final telemetry = build();
      await telemetry.start();
      expect(sdk.options!.replay.onErrorSampleRate, 1.0);

      await settings.setShareReplay(false);
      await pumpEventQueue();

      expect(telemetry.running, isTrue, reason: 'reporting stayed on');
      expect(sdk.inits, 2, reason: 'the SDK came back up');
      // Without this a second `init` on top of a live hub would pass, which is
      // this file's own second historical bug.
      expect(sdk.closes, 1, reason: 'it went down before it came back');
      expect(sdk.rates, [1.0, 0.0]);
      expect(allSinksInstalled, isTrue);
    });

    test('the replay switch brings it back up when switched back on', () async {
      // The other direction, which is the one that *starts* recording - and
      // the only one a user who switched replay off ever exercises again.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_replay': false,
      });
      final telemetry = build();
      await telemetry.start();
      expect(sdk.rates, [0.0]);

      await settings.setShareReplay(true);
      await pumpEventQueue();

      expect(telemetry.running, isTrue);
      expect(sdk.rates, [0.0, 1.0]);
      expect(allSinksInstalled, isTrue);
    });

    test('a replay switch whose shutdown fails stops rather than looping', () async {
      // `_tearDown` leaves `_running` true when the close fails, on purpose,
      // so the switch cannot claim something that did not happen. Applying a
      // replay change means calling `stop` while the main switch still says
      // on. Those two together had no end: the failed stop left the same
      // disagreement, and `stop`'s `finally` reconciled straight back into it.
      //
      // Not a spin - each cycle is synchronous work plus a microtask, so the
      // event queue is never reached and no timer fires. A `Timeout` on this
      // test could not have caught it; the fake's `closeThrowsLimit` is what
      // keeps a regression here from wedging the run.
      final telemetry = build();
      await telemetry.start();
      sdk.closeThrows = StateError('the native layer would not go down');
      sdk.closeThrowsLimit = 4;

      await settings.setShareReplay(false);
      await pumpEventQueue();

      expect(sdk.closes, 1, reason: 'one attempt, not one per microtask');
      expect(telemetry.running, isTrue, reason: 'the close did not happen');
      // And the switch still works afterwards: putting it back where the SDK
      // actually is drops the latch, so a later genuine change is applied.
      await settings.setShareReplay(true);
      await pumpEventQueue();
      expect(sdk.closes, 1, reason: 'nothing to do, the SDK has this rate');
    });

    test('a replay tap during a start is not dropped', () async {
      // `_settlingTowardReplay`'s entire reason to exist. `_reconcile` declines
      // to act while `_settling`, so a tap landing after the plan was built
      // would otherwise be lost - and lost in the direction that keeps
      // recording with the switch off. Toggling from inside the injected
      // `init` puts the tap exactly in that window.
      //
      // Deleting the branch leaves `inits` at 1, which is what this asserts
      // against; every other case in this file reaches it while idle and so
      // passes either way.
      var toggled = false;
      final telemetry = Telemetry(
        settings: settings,
        dsn: 'https://key@o1.ingest.de.sentry.io/2',
        init: (configure) async {
          await sdk.init(configure);
          if (!toggled) {
            toggled = true;
            await settings.setShareReplay(false);
          }
        },
        shutdown: sdk.close,
      );

      await telemetry.start();
      await pumpEventQueue();

      expect(sdk.inits, 2, reason: 'the tap was picked up after the start');
      expect(sdk.rates, [1.0, 0.0], reason: 'and it carried the new rate');
      expect(telemetry.running, isTrue);
    });

    test('the replay switch does nothing while sharing is off', () async {
      // Nothing is running for a replay to be attached to, so there is no
      // reason to bring an SDK up to tell it about one. The Diagnostics screen
      // leaves the row out in this state for the same reason.
      //
      // Seeded **off** and switched **on**, which is what makes this a test.
      // The other way round there is nothing to reconcile - `_runningWithReplay`
      // is still at its initialiser because `start()` bailed - so three
      // separate guards each make it a no-op and the case passed with the whole
      // replay branch deleted.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_logs': false,
        'diagnostics.share_replay': false,
      });
      final telemetry = build();
      await telemetry.start();
      expect(sdk.inits, 0);

      await settings.setShareReplay(true);
      await pumpEventQueue();

      expect(telemetry.running, isFalse);
      expect(sdk.inits, 0);
    });

    test('a build that launched with it off can still turn it on', () async {
      // The mirror case: `start()` returned before the listener was ever
      // registered, so for a user who opted out last session the switch was
      // inert for the whole of the next one.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_logs': false,
      });
      final telemetry = build();
      await telemetry.start();
      expect(telemetry.running, isFalse);

      await settings.setShareLogs(true);
      await pumpEventQueue();

      expect(telemetry.running, isTrue);
      expect(allSinksInstalled, isTrue);
    });

    test('a notify that changed nothing does not restart the SDK', () async {
      final telemetry = build();
      await telemetry.start();

      await settings.setShareLogs(true);
      await pumpEventQueue();

      expect(sdk.inits, 1, reason: 'already on, so nothing to do');
      expect(sdk.closes, 0);
    });
  });
}
