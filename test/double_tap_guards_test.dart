import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/components/archive/models/fap.dart';
import 'package:qunleashed/components/navigation.dart';
import 'package:qunleashed/pages/apps/actions.dart';
import 'package:qunleashed/pages/archive/browser/controller.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/storage.dart';

/// One gesture must not run an action twice. #244.
///
/// On a desktop a double click is one natural gesture, which is why these
/// survived: they are easy to hit with a mouse and nearly impossible by touch.
/// The shape is always the same - a handler awaits slow device work and *then*
/// pushes a page or writes something, with the control enabled throughout.
///
/// Every case here parks the device call rather than letting it answer, because
/// the window the bug lives in is exactly the time the device takes. A test
/// where the first call has already finished cannot tell a guard from no guard.
///
/// What is asserted is the number of *requests*, not a log line:
/// `LogService._remember` drops a consecutive identical body, so `hasLength(1)`
/// cannot tell "said once" from "said twice".
class _ParkingFlipper implements FlipperClient {
  /// Completed by a test to let the parked call answer. Null means answer at
  /// once.
  Completer<void>? gate;

  /// Every request this was asked for, in order, as `kind(argument)`.
  final calls = <String>[];

  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  bool get isRpcReady => connected;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  Transport? get transport => null;

  @override
  bool isLinkDropError(Object e) => false;

  /// Straight through. `runTask` binds the BLE session and is not a mutex -
  /// which is half of why these bugs exist, so a fake that serialised here
  /// would hide them.
  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  @override
  String? getName() => 'TestFlipper';

  @override
  Future<String> awaitName() async => 'TestFlipper';

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    await send((_) async {});
    return const [];
  }

  Future<List<Main>> _answer(Main request) async {
    if (request.hasStorageListRequest()) {
      calls.add('storageList(${request.storageListRequest.path})');
      await gate?.future;
      return [Main(storageListResponse: ListResponse())];
    }
    if (request.hasAppStartRequest()) {
      calls.add('appStart(${request.appStartRequest.name})');
      await gate?.future;
      return const [];
    }
    calls.add('unexpected ${request.whichContent()}');
    return const [];
  }

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    final frames = await _answer(request);
    for (final frame in frames) {
      onFrame?.call(frame);
    }
    return frames;
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await _answer(request);
    final items = <T>[];
    for (final frame in frames) {
      onFrame?.call(frame);
      final picked = pick(frame);
      if (picked != null) items.add(picked);
    }
    return FlipperRpcBatch<T>(
      commandId: 0,
      request: request,
      frames: frames,
      items: items,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _listCalls(_ParkingFlipper client) =>
    client.calls.where((c) => c.startsWith('storageList')).length;

int _startCalls(_ParkingFlipper client) =>
    client.calls.where((c) => c.startsWith('appStart')).length;

FapFavorite _fav(String path) =>
    FapFavorite(remotePath: path, name: path.split('/').last);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('listing a folder in the file manager', () {
    late _ParkingFlipper client;
    late FileManagerController ctrl;

    setUp(() {
      client = _ParkingFlipper();
      ctrl = FileManagerController(client: client, initialPath: '/ext');
      addTearDown(ctrl.dispose);
    });

    test('happens once when the second tap arrives while it is out', () async {
      client.gate = Completer<void>();
      final first = ctrl.refresh();
      final second = ctrl.refresh();
      client.gate!.complete();
      await Future.wait([first, second]);

      expect(_listCalls(client), 1);
    });

    // The guard has to be released, or the folder can never be re-listed - and
    // a refresh is what every operation in the page ends with.
    test('happens again once the first listing has answered', () async {
      await ctrl.refresh();
      await ctrl.refresh();

      expect(_listCalls(client), 2);
    });

    // The regression a bare `if (_loading) return;` introduces, which is why
    // the guard is keyed on the path: `open()` moves the path and then calls
    // refresh, so a flag would skip the new folder's listing altogether and
    // leave the previous folder's entries on screen under the new path.
    test('still happens for a folder opened while one is out', () async {
      client.gate = Completer<void>();
      final first = ctrl.refresh();
      final opened = ctrl.open('/ext/subghz');
      client.gate!.complete();
      await Future.wait([first, opened]);

      expect(client.calls, ['storageList(/ext)', 'storageList(/ext/subghz)']);
    });
  });

  group('launching a favourited app', () {
    late _ParkingFlipper client;
    late ArchiveController ctrl;

    setUp(() {
      client = _ParkingFlipper();
      ctrl = ArchiveController(client: client, storage: ArchiveStorage());
      addTearDown(ctrl.dispose);
    });

    test('starts the app once when tapped twice', () async {
      client.gate = Completer<void>();
      final first = ctrl.launchFapFavorite(_fav('/ext/apps/Tools/nfc.fap'));
      final second = ctrl.launchFapFavorite(_fav('/ext/apps/Tools/nfc.fap'));
      client.gate!.complete();

      expect(await first, isTrue);
      expect(_startCalls(client), 1);
      // Null and not false: false is a launch that failed, and the page shows
      // a toast for it. The second tap has nothing to report either way.
      expect(await second, isNull);
    });

    test('starts it again on a later tap', () async {
      await ctrl.launchFapFavorite(_fav('/ext/apps/Tools/nfc.fap'));
      await ctrl.launchFapFavorite(_fav('/ext/apps/Tools/nfc.fap'));

      expect(_startCalls(client), 2);
    });

    // Why the key is the path: two taps on two different cards is not the
    // gesture this is about, and only the Flipper gets to refuse it.
    test('does not block a different app launched meanwhile', () async {
      client.gate = Completer<void>();
      final first = ctrl.launchFapFavorite(_fav('/ext/apps/Tools/nfc.fap'));
      final other = ctrl.launchFapFavorite(_fav('/ext/apps/Games/snake.fap'));
      client.gate!.complete();
      await Future.wait([first, other]);

      expect(_startCalls(client), 2);
    });
  });

  group('handing the screen to the remote control', () {
    setUp(
      () => registerRoute(
        AppRoute.remoteControl,
        (context, args) => const Text('remote control'),
      ),
    );

    // launchApp is what the catalog, the app manager and the installer all
    // call, so the guard inside it is one guard for three pages.
    testWidgets('starts the app once for two presses', (tester) async {
      final gate = Completer<void>();
      var starts = 0;
      Future<void> start() async {
        starts++;
        await gate.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => launchApp(context, start),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(starts, 1);
      expect(find.text('remote control'), findsOneWidget);
    });

    test('lets the next launch through once the first is done', () async {
      var starts = 0;
      // No context is needed to prove the release: launchApp bails out of the
      // push itself when the context has gone, and the flag is cleared in a
      // finally either way.
      await launchApp(_DeadContext(), () async => starts++);
      await launchApp(_DeadContext(), () async => starts++);

      expect(starts, 2);
    });
  });

  group('a card whose whole job is a push', () {
    // iOS, because that is the only place this is reachable: the Cupertino
    // slide leaves the pushing control exposed for the whole transition, while
    // the Zoom transition every other platform gets is opaque from the first
    // frame and absorbs the second click. Through the theme rather than
    // `debugDefaultTargetPlatformOverride`, which the test framework checks is
    // unset by the time the body returns.
    Widget app() => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: const _PushingPage(),
    );

    testWidgets('pushes one page for two taps', (tester) async {
      await tester.pumpWidget(app());

      await tester.tap(find.text('open'));
      // One frame, so the push has happened and the transition has not
      // finished - which is the window the second click lands in.
      await tester.pump();
      await tester.tap(find.text('open'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('pushed'), findsOneWidget);
    });

    testWidgets('pushes again after the pushed page is popped', (tester) async {
      await tester.pumpWidget(app());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('pushed'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('pushed'), findsOneWidget);
    });
  });
  // A ratchet in ADR 0004's sense, and the weakest thing in this file by
  // design. A widget test of each of these would cost a backend fake and a
  // DeviceScope per page - seven harnesses to assert seven copies of one line
  // whose behaviour is already pinned above. What it cannot do is prove the
  // guard sits in the right place; what it does is notice one going missing,
  // which is the mutation nothing else here would catch.
  //
  // A site legitimately rewritten belongs off this list, in the same commit.
  group('the sites whose whole handler is a push', () {
    const guarded = [
      'lib/pages/tools/infrared/brands_page.dart',
      'lib/pages/tools/infrared/categories_page.dart',
      'lib/pages/tools/infrared/page.dart',
      'lib/pages/tools/paint/manager/page.dart',
      'lib/pages/tools/overview/page.dart',
      'lib/pages/archive/overview/page.dart',
      'lib/pages/flibler/project/page.dart',
    ];

    test('all still ask whether their page is on top', () {
      final missing = [
        for (final path in guarded)
          if (!io.File(path).readAsStringSync().contains('isTopRoute(context)'))
            path,
      ];

      expect(
        missing,
        isEmpty,
        reason: 'a tap handler lost its #244 guard against a double push',
      );
    });
  });
}

/// A page whose button does what the guarded sites do: push, and nothing else.
class _PushingPage extends StatelessWidget {
  const _PushingPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () {
          if (!isTopRoute(context)) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('pushed'))),
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  );
}

/// A context that is never mounted, for the paths that only ask that.
class _DeadContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
