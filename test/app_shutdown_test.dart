import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/shutdown.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/services/telemetry/telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'telemetry_sinks.dart';

/// Giving the serial port back before the window takes the process down.
///
/// The submodule's own suite covers the release itself - `port.close()` running
/// in the isolate that opened it, rather than that isolate being killed out
/// from under it. Nothing covered that the release is ever *reached*, and the
/// app side is its only caller: drop `setPreventClose` and the window closes
/// while the disconnect is still in flight, which is the reported bug restored
/// with all of that work inert.
///
/// Driven through the real `window_manager` channel in both directions - the
/// plugin is a `MethodChannel` plus a `setMethodCallHandler`, so the channel is
/// the seam. The close arrives the way the platform delivers it, which
/// exercises the `addListener` wiring rather than calling `onWindowClose()` by
/// hand.
class _RecordingClient implements FlipperClient {
  /// [steps] is the shared ordering list when a case needs one, so what the
  /// client was asked to do and what the window was asked to do can be
  /// asserted as one sequence.
  _RecordingClient({this.parkDisconnect = false, List<String>? steps})
    : calls = steps ?? <String>[];

  /// Leaves `disconnectAll` in flight for ever: a device that will not answer.
  final bool parkDisconnect;

  final List<String> calls;

  @override
  Future<void> disconnectAll() {
    calls.add('disconnectAll');
    if (parkDisconnect) return Completer<void>().future;
    return Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A `Telemetry` that is actually reporting, writing what it is asked to do
/// into [steps] - the one list this file asserts order on.
///
/// Injected rather than real for the reason `telemetry_lifecycle_test.dart`
/// gives at length: `QU_SENTRY_DSN` is a `String.fromEnvironment` and no
/// `--dart-define` reaches `flutter test`, so without the seams `start()`
/// returns at its own guard and the close can never run.
///
/// One shared list rather than counters, because the order is the thing: an
/// earlier version counted the closes and asserted `platform.last` separately,
/// and moving the flush *below* `destroy` left every assertion green - a
/// mocked `destroy` answers and the test keeps running where the real process
/// does not. An exact-sequence match cannot be fooled that way, and it pins
/// "exactly one init" at the same time, which is what says `closeForExit` is a
/// one-way door rather than a rename of `stop`.
///
/// [closeHangs] leaves the close in flight for ever: a report retrying against
/// a network that is not there, which is the shape the budget exists for.
Future<Telemetry> startReporting({
  required List<String> steps,
  bool closeHangs = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final telemetry = Telemetry(
    settings: DiagnosticsSettings(),
    dsn: 'https://key@o0.ingest.sentry.io/1',
    init: (_) async => steps.add('init'),
    shutdown: () {
      steps.add('flush');
      return closeHangs ? Completer<void>().future : Future<void>.value();
    },
  );
  await telemetry.start();
  expect(
    telemetry.running,
    isTrue,
    reason: 'a flush of a telemetry that never came up proves nothing',
  );
  // `start()` wires four process-wide sinks and raises flipperlib's level, and
  // the hanging case never reaches the teardown that takes them off - so
  // without this they stay pointed at a dead `Telemetry` for every case after
  // it.
  addTearDown(resetTelemetrySinks);
  return telemetry;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppShutdown', () {
    const channel = MethodChannel('window_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    late List<String> platform;
    late List<int> exits;
    late bool answerDestroy;

    setUp(() {
      platform = [];
      exits = [];
      answerDestroy = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        platform.add(
          call.method == 'setPreventClose'
              ? 'setPreventClose:${(call.arguments as Map)['isPreventClose']}'
              : call.method,
        );
        // The Windows runner tears the engine down inside WM_DESTROY, so on a
        // real success this reply never comes back at all.
        if (call.method == 'destroy' && !answerDestroy) {
          return Completer<Object?>().future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        LinkService.instance.suspended = false;
      });
    });

    /// Defaults to a telemetry nobody gave a DSN, which is every build by
    /// default: `stop()` returns at its own guard, so the cases below that are
    /// about the link keep their original timings.
    AppShutdown install(_RecordingClient client, {Telemetry? telemetry}) {
      final shutdown = AppShutdown(
        client,
        telemetry ?? Telemetry(settings: DiagnosticsSettings(), dsn: ''),
        exitProcess: exits.add,
      );
      // windowManager keeps a process-wide ObserverList, so a listener left
      // behind here fires inside later cases.
      addTearDown(() => windowManager.removeListener(shutdown));
      return shutdown;
    }

    /// Brings a reporting `Telemetry` up, outside the fake-async zone.
    ///
    /// `Telemetry.start()` awaits `PackageInfo.fromPlatform()`, and a
    /// platform-channel reply is delivered by the real event loop - inside the
    /// `FakeAsync` that `pump` runs in it never arrives at all, so the case
    /// hangs instead of failing. `telemetry_lifecycle_test.dart` does not need
    /// this because it uses `test`, not `testWidgets`.
    Future<Telemetry> reporting(
      WidgetTester tester, {
      bool closeHangs = false,
    }) async => (await tester.runAsync(
      () => startReporting(steps: platform, closeHangs: closeHangs),
    ))!;

    /// The X, delivered the way the platform delivers it.
    Future<void> clickTheX() => messenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onEvent', {'eventName': 'close'}),
      ),
      (_) {},
    );

    testWidgets('holds the window open and listens for the close', (
      tester,
    ) async {
      final shutdown = install(_RecordingClient());
      await shutdown.install();

      expect(platform, ['ensureInitialized', 'setPreventClose:true']);
      // Without this the window closes while the disconnect is still running,
      // and the native side never asks again.
      expect(windowManager.hasListeners, isTrue);
    });

    testWidgets('releases the link, then destroys the window, in that order', (
      tester,
    ) async {
      final client = _RecordingClient();
      final shutdown = install(client);
      await shutdown.install();

      await clickTheX();
      await tester.pump(const Duration(seconds: 1));

      expect(client.calls, ['disconnectAll', 'dispose']);
      // Destroying first is the bug: the engine goes down with the port still
      // open, which is what left a COM port behind.
      expect(platform.last, 'destroy');
    });

    // The keeper watches sessionsStream and debounces a reconcile behind it,
    // and a disconnect from here is not a user disconnect - so without this it
    // re-opens the serial port in the middle of the teardown, and the process
    // then dies holding a handle it has just acquired.
    testWidgets('suspends the keeper before anything disconnects', (
      tester,
    ) async {
      LinkService.instance.suspended = false;
      final client = _RecordingClient(parkDisconnect: true);
      final shutdown = install(client);
      await shutdown.install();

      await clickTheX();
      await tester.pump();

      expect(client.calls, [
        'disconnectAll',
      ], reason: 'the case has to be mid-disconnect for this to mean anything');
      expect(LinkService.instance.suspended, isTrue);

      // Lets the two budgets expire, so nothing is left pending.
      await tester.pump(const Duration(seconds: 10));
    });

    // A disconnect that never answers used to hold the whole exit open: one
    // three-second budget was spread across the whole of dispose(), the window
    // stayed up, and the user reached for Task Manager.
    testWidgets('a disconnect that never answers still reaches the window', (
      tester,
    ) async {
      final client = _RecordingClient(parkDisconnect: true);
      final shutdown = install(client);
      await shutdown.install();

      await clickTheX();
      await tester.pump(const Duration(seconds: 3));
      expect(platform, isNot(contains('destroy')), reason: 'still trying');

      await tester.pump(const Duration(seconds: 5));
      expect(platform.last, 'destroy');
    });

    // The exit of last resort. `window_manager`'s Windows `destroy` is
    // `PostQuitMessage(0)` and answers at once, so the usual case is that this
    // runs - but a `destroy` that is swallowed, or a window still standing
    // afterwards, leaves prevent-close on with nothing left that can close it.
    // That was a window only Task Manager could close.
    testWidgets('exits itself when the window survives being destroyed', (
      tester,
    ) async {
      answerDestroy = false;
      final shutdown = install(_RecordingClient());
      await shutdown.install();

      await clickTheX();
      await tester.pump(const Duration(seconds: 10));

      expect(exits, [0]);
    });

    // What the exit path reported, which for a while was nothing. Sentry
    // batches kept lines five seconds behind the line that produced them, and
    // an exit that hits none of its budgets is quicker than that - so the warn,
    // and whatever the two disconnects said about a wedged transport, was still
    // in the batcher when the process went. A local Windows build produced
    // three kept lines on the way out and the project received none of them.
    testWidgets('drains the reports before the window goes', (tester) async {
      final telemetry = await reporting(tester);
      final client = _RecordingClient(steps: platform);
      final shutdown = install(client, telemetry: telemetry);
      await shutdown.install();

      await clickTheX();
      await tester.pump(const Duration(seconds: 1));

      // The whole sequence, because every part of its order is load-bearing:
      // the flush after the two disconnects, so their lines are in the batcher
      // when it drains; before `destroy`, because on Windows the process is
      // winding down after that; and one `init`, never a second - `stop()`,
      // which this used to call, ends by reconciling against a switch that is
      // still on, so it drained the batcher and then brought the SDK back up,
      // native layer and all, into a window being destroyed.
      expect(platform, [
        'init',
        'ensureInitialized',
        'setPreventClose:true',
        'disconnectAll',
        'dispose',
        'flush',
        'destroy',
      ]);
      expect(telemetry.running, isFalse);
    });

    // The budget. `Future.timeout` cancels nothing, so the close is still in
    // flight when the window is destroyed - which is fine, and is the point:
    // the alternative is a window standing open while a report retries against
    // a network that is not there.
    testWidgets('a flush that never answers still reaches the window', (
      tester,
    ) async {
      final telemetry = await reporting(tester, closeHangs: true);
      final client = _RecordingClient(steps: platform);
      final shutdown = install(client, telemetry: telemetry);
      await shutdown.install();

      await clickTheX();
      await tester.pump(const Duration(seconds: 1));
      expect(platform, contains('flush'), reason: 'and it has begun');
      expect(platform, isNot(contains('destroy')), reason: 'still flushing');

      await tester.pump(const Duration(seconds: 3));
      expect(platform.last, 'destroy');
      // And the switch still says reporting is up, because it may well be:
      // the close never completed, so `closeForExit` never reached the line
      // that clears the flag. `Future.timeout` cancels nothing.
      expect(telemetry.running, isTrue);
      expect(
        platform.where((s) => s == 'init'),
        hasLength(1),
        reason: 'and nothing restarted it',
      );
    });

    testWidgets('a second click on the X does not disconnect twice', (
      tester,
    ) async {
      final client = _RecordingClient(parkDisconnect: true);
      final shutdown = install(client);
      await shutdown.install();

      await clickTheX();
      await tester.pump();
      await clickTheX();
      await tester.pump();

      expect(client.calls, ['disconnectAll']);

      await tester.pump(const Duration(seconds: 10));
    });
  });
}
