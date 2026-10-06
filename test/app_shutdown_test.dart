import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/shutdown.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:window_manager/window_manager.dart';

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
  _RecordingClient({this.parkDisconnect = false});

  /// Leaves `disconnectAll` in flight for ever: a device that will not answer.
  final bool parkDisconnect;

  final calls = <String>[];

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

    AppShutdown install(_RecordingClient client) {
      final shutdown = AppShutdown(client, exitProcess: exits.add);
      // windowManager keeps a process-wide ObserverList, so a listener left
      // behind here fires inside later cases.
      addTearDown(() => windowManager.removeListener(shutdown));
      return shutdown;
    }

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

    // destroy() not answering is the *success* shape on Windows: Dart stops
    // inside WM_DESTROY and nothing after it runs. When it does answer, or
    // never answers and the process is still here, the window is standing with
    // prevent-close on and nothing left that can close it.
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
