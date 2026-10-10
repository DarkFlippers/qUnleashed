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
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/http/app_http.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/services/telemetry/telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quiet_log.dart';

/// Why this file reads the console and not `LogService.keptSink`.
///
/// Every other logging test observes what reporting *sends*, through the
/// recorder in `kept_lines.dart`. This one cannot, for two reasons that both
/// come down to it being the file that owns that static:
///
///  * [anySinkInstalled] asserts on whether the hook is set at all, so a
///    recorder sitting in it makes "nothing was installed" unobservable - and
///    the no-DSN and switch-off cases are exactly the ones that must install
///    nothing;
///  * `Telemetry.stop()` clears all four hooks, so a recorder is gone by the
///    time the close failure is logged, and `may still be running` reaches
///    nobody.
///
/// Which is not a gap: none of the lines asserted on here *can* be reported.
/// They say reporting is off, has no DSN, or could not be shut down, and the
/// console is the only channel left in all three cases. `hasLength(printing)`
/// rather than `hasLength(1)` so the file still means something if it is ever
/// added to CI's quiet job.
int get onConsole => LogService.printing ? 1 : 0;

/// A stand-in for the SDK's own lifecycle.
class _FakeSdk {
  int inits = 0;
  int closes = 0;

  /// Thrown by [init] when set, to drive the half-initialised state.
  Object? initThrows;

  /// Thrown by [close] when set.
  Object? closeThrows;

  /// The options the configure callback produced, so the block is checkable.
  SentryFlutterOptions? options;

  Future<void> init(void Function(SentryFlutterOptions) configure) async {
    inits += 1;
    final built = SentryFlutterOptions();
    configure(built);
    options = built;
    final boom = initThrows;
    if (boom != null) throw boom;
  }

  Future<void> close() async {
    closes += 1;
    final boom = closeThrows;
    if (boom != null) throw boom;
  }
}

/// Whether any of the four hooks is installed.
bool get anySinkInstalled =>
    guardedFailureSink != null ||
    LogService.keptSink != null ||
    LogService.breadcrumbSink != null ||
    AppHttp.exchangeSink != null;

/// Whether all four are.
bool get allSinksInstalled =>
    guardedFailureSink != null &&
    LogService.keptSink != null &&
    LogService.breadcrumbSink != null &&
    AppHttp.exchangeSink != null;

void main() {
  late _FakeSdk sdk;
  late DiagnosticsSettings settings;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sdk = _FakeSdk();
    settings = DiagnosticsSettings();
  });

  tearDown(() {
    guardedFailureSink = null;
    LogService.keptSink = null;
    LogService.breadcrumbSink = null;
    AppHttp.exchangeSink = null;
    Log.sink = null;
    Log.level = FlipperLogLevel.info;
  });

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
      final lines = await printedAsync(telemetry.start);

      expect(sdk.inits, 0);
      expect(telemetry.running, isFalse);
      expect(anySinkInstalled, isFalse);
      expect(lines.where((l) => l.contains('no DSN')), hasLength(onConsole));
    });

    test('the switch being off installs nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostics.share_logs': false,
      });
      final telemetry = build();
      final lines = await printedAsync(telemetry.start);

      expect(sdk.inits, 0);
      expect(anySinkInstalled, isFalse);
      expect(lines.where((l) => l.contains('Settings')), hasLength(onConsole));
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

    test('replay stays off, which is phase 3 behind §6.4\'s gate', () async {
      await build().start();
      final replay = sdk.options!.replay;
      expect(replay.sessionSampleRate, anyOf(isNull, 0.0));
      expect(replay.onErrorSampleRate, anyOf(isNull, 0.0));
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

      final lines = await printedAsync(telemetry.start);

      expect(telemetry.running, isFalse);
      expect(sdk.closes, 1, reason: 'the live hub was closed');
      expect(anySinkInstalled, isFalse);
      expect(
        lines.where((l) => l.contains('[Telemetry] init failed')),
        hasLength(onConsole),
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
