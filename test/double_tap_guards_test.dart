import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
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
import 'package:qunleashed/pages/tools/plotter/page.dart';
import 'package:qunleashed/services/archive/storage.dart';

import 'firmware_fixture.dart';

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

    // Coalesced, not dropped. Dropping it was the first draft and it made
    // `await refresh()` a lie: ten call sites in the page change the folder and
    // then refresh it, so a dropped listing leaves the pre-change entries on
    // screen with nothing said. What a second tap costs is one *sequential*
    // listing instead of a second concurrent one.
    test('runs a second listing after the first, not alongside it', () async {
      client.gate = Completer<void>();
      final first = ctrl.refresh();
      final second = ctrl.refresh();
      // Still one while the first is out: the second has not started yet.
      expect(_listCalls(client), 1);
      client.gate!.complete();
      await Future.wait([first, second]);

      expect(_listCalls(client), 2);
    });

    // However many arrive in the window, they share one trailing listing.
    test('costs one extra listing for five taps, not five', () async {
      client.gate = Completer<void>();
      final all = [for (var i = 0; i < 5; i++) ctrl.refresh()];
      client.gate!.complete();
      await Future.wait(all);

      expect(_listCalls(client), 2);
    });

    // The contract the ten mutating call sites rely on: when the future
    // completes, a listing that started *after* the call has landed.
    test('is fresh for a caller that arrived while one was out', () async {
      client.gate = Completer<void>();
      final first = ctrl.refresh();
      final after = ctrl.refresh();
      client.gate!.complete();
      await after;

      expect(_listCalls(client), 2);
      await first;
    });

    test('happens again once the first listing has answered', () async {
      await ctrl.refresh();
      await ctrl.refresh();

      expect(_listCalls(client), 2);
    });

    // The release, which the count above cannot see: left in the map, the
    // finished listing is still "in flight", so the next refresh coalesces
    // onto it and starts a microtask later instead of at once. Two listings
    // either way - the tell is *when* the second one starts.
    test('starts the next listing at once, not a hop later', () async {
      await ctrl.refresh();

      final second = ctrl.refresh();

      expect(_listCalls(client), 2);
      await second;
    });

    // Both halves of the stale-listing rule, which is what lets the maps stay
    // keyed per path without the screen paying for it.
    // Neither future is awaited before the gate opens: both listings are
    // parked in the fake, and awaiting one first would wait on a gate this
    // body has not opened yet.
    test('writes nothing for a folder the user has already left', () async {
      client.gate = Completer<void>();
      final first = ctrl.refresh();
      final opened = ctrl.open('/ext/subghz');
      client.gate!.complete();
      await Future.wait([first, opened]);

      expect(ctrl.path, '/ext/subghz');
      // The listing of `/ext` landed last and must have written nothing: not
      // its entries, and not the `loading` of the one that followed it.
      expect(ctrl.loading, isFalse);
    });

    // Its own controller, because this one is disposed inside the body and
    // ChangeNotifier refuses a second dispose from the teardown.
    test('sends no trailing listing once the page has gone', () async {
      final closing = FileManagerController(
        client: client,
        initialPath: '/ext',
      );
      client.gate = Completer<void>();
      final first = closing.refresh();
      final second = closing.refresh();
      closing.dispose();
      client.gate!.complete();
      await Future.wait([first, second]);

      expect(_listCalls(client), 1);
    });

    // The regression a bare `if (_loading) return;` introduces, which is why
    // this is keyed on the path at all: `open()` moves the path and then calls
    // refresh, so a flag would skip the new folder's listing altogether and
    // leave the previous folder's entries on screen under the new path. A
    // different path also starts at once rather than waiting its turn.
    test('still happens for a folder opened while one is out', () async {
      client.gate = Completer<void>();
      final first = ctrl.refresh();
      final opened = ctrl.open('/ext/subghz');
      expect(client.calls, ['storageList(/ext)', 'storageList(/ext/subghz)']);
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
    late _CountingObserver pushes;

    setUp(() {
      pushes = _CountingObserver();
      registerRoute(
        AppRoute.remoteControl,
        (context, args) => const Text('remote control'),
      );
    });

    // Counting presses of one button through one `launchApp`, which is what
    // the catalog, the app manager and the installer all call - so the guard
    // inside it is one guard for three pages.
    //
    // The pushed remote control is counted at the navigator, not with
    // `find.text`: two stacked remote controls would also satisfy
    // findsOneWidget, because the obscured route is offstage and finders skip
    // offstage widgets.
    Future<VoidCallback> pumpLauncher(
      WidgetTester tester, {
      required Future<void> Function() start,
      String target = 'nfc',
    }) async {
      late VoidCallback press;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [pushes],
          home: Builder(
            builder: (context) {
              press = () => launchApp(context, start, target: target);
              return ElevatedButton(
                onPressed: press,
                child: const Text('open'),
              );
            },
          ),
        ),
      );
      return press;
    }

    testWidgets('starts the app once for two presses', (tester) async {
      final gate = Completer<void>();
      var starts = 0;
      final press = await pumpLauncher(
        tester,
        start: () async {
          starts++;
          await gate.future;
        },
      );

      press();
      press();
      gate.complete();
      await tester.pumpAndSettle();

      expect(starts, 1);
      expect(pushes.count, 1);
    });

    // The release, on the path that *did* push - which is the mutation that
    // matters, because a flag left set here wedges app launching process-wide
    // for the rest of the session. An earlier version of this test used an
    // unmounted context for both launches, so it never covered this leg; the
    // mutation it was meant to catch was caught by that flag leaking into the
    // next test instead, which is not the same thing as a test.
    testWidgets('lets the next press through once the first is done', (
      tester,
    ) async {
      var starts = 0;
      final press = await pumpLauncher(tester, start: () async => starts++);

      press();
      await tester.pumpAndSettle();
      press();
      await tester.pumpAndSettle();

      expect(starts, 2);
      expect(pushes.count, 2);
    });

    // Why it is keyed: Run on a *different* app is a thing a user does, and
    // the answer to it belongs to the Flipper - which says "busy" through the
    // dialog this function shows - rather than to a dead button on three
    // pages. Unkeyed, the second app was refused in silence for up to the
    // fifteen seconds appStart allows.
    testWidgets('does not block a different app launched meanwhile', (
      tester,
    ) async {
      final gate = Completer<void>();
      var starts = 0;
      Future<void> start() async {
        starts++;
        await gate.future;
      }

      final press = await pumpLauncher(tester, start: start, target: 'nfc');
      press();
      // Not awaited before the gate is completed: both launches are parked in
      // `start`, and awaiting one here would wait for a gate this body has not
      // opened yet.
      final second = launchApp(_DeadContext(), start, target: 'snake');
      expect(starts, 2);

      gate.complete();
      await second;
      await tester.pumpAndSettle();

      expect(starts, 2);
    });

    test('releases the key even when the page has gone', () async {
      var starts = 0;
      await launchApp(_DeadContext(), () async => starts++, target: 'nfc');
      await launchApp(_DeadContext(), () async => starts++, target: 'nfc');

      expect(starts, 2);
    });
  });

  group('a card whose whole job is a push', () {
    // The platform is pinned so the transition is a known one, and nothing
    // here depends on which: the handler is driven directly, so whether a real
    // pointer would have reached the control mid-transition never comes up.
    // `isTopRoute`'s own doc comment carries what the platforms actually do.
    // Through the theme rather than `debugDefaultTargetPlatformOverride`,
    // which the test framework checks is unset by the time the body returns.
    late _CountingObserver pushes;

    setUp(() => pushes = _CountingObserver());

    Widget app() => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      navigatorObservers: [pushes],
      home: const _PushingPage(),
    );

    // Two things in this test were wrong before a mutation run said so, and
    // both are the same mistake: asserting something other than the thing.
    //
    // `expect(find.text('pushed'), findsOneWidget)` passes with *two* pages
    // stacked, because a route obscured by an opaque one is offstage and
    // finders skip offstage widgets by default. So the navigator is asked
    // instead, which is also independent of how the handler is written.
    //
    // And two `tester.tap`s do not make the second activation happen: a tap
    // mid-transition lands on the incoming page rather than the button, so
    // that version passed with the guard turned into `=> true` - it proved the
    // pointer missed. Driving the handler is the gesture with Flutter's
    // hit-testing taken out of the question.
    testWidgets('pushes one page for two activations', (tester) async {
      await tester.pumpWidget(app());

      final open = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      open.onPressed!();
      // One frame, so the push has happened and the transition has not
      // finished - the window the second click lands in.
      await tester.pump();
      open.onPressed!();
      await tester.pumpAndSettle();

      expect(pushes.count, 1);
    });

    // And the same with no frame in between at all, which is the push being
    // in the navigator's history synchronously rather than a frame later.
    testWidgets('pushes one page for two activations in one frame', (
      tester,
    ) async {
      await tester.pumpWidget(app());

      final open = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      open.onPressed!();
      open.onPressed!();
      await tester.pumpAndSettle();

      expect(pushes.count, 1);
    });

    // The `?? true` fallback: every caller in the app is under a route, so
    // nothing here reached this branch, and turning it into `?? false` passed
    // the whole suite while silently disabling eight guarded navigations under
    // test.
    testWidgets('says yes where there is no route to ask about', (
      tester,
    ) async {
      late BuildContext outside;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            outside = context;
            return const SizedBox();
          },
        ),
      );

      expect(isTopRoute(outside), isTrue);
    });

    testWidgets('pushes again after the pushed page is popped', (tester) async {
      await tester.pumpWidget(app());
      final open = tester.element(find.text('open'));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('pushed'))).pop();

      // Before any pump, and this is the assertion worth having: a draft of
      // isTopRoute's doc claimed a tap inside the pop's exit animation was
      // refused. `pop()` flushes the history synchronously, so the page below
      // is current again at once - and the alternative instrument, a flag
      // cleared on the pushed route's future, clears at this same instant.
      expect(isTopRoute(open), isTrue);

      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(pushes.count, 2);
      expect(find.text('pushed'), findsOneWidget);
    });

    // The other half of what it refuses, and the reason it is not folded into
    // openRoute: anything above the page counts, a dialog included.
    testWidgets('refuses while a dialog is up', (tester) async {
      await tester.pumpWidget(app());
      final open = tester.element(find.text('open'));

      unawaited(
        showDialog<void>(context: open, builder: (_) => const Text('dialog')),
      );
      await tester.pumpAndSettle();

      expect(isTopRoute(open), isFalse);
    });
  });
  // The plotter's picker, which is the firmware bug of #250 in a page that
  // needs no device fake: a flag armed only after the picker returns, so both
  // buttons stayed live while the dialog was open. The picker is parked for as
  // long as the dialog would be, which is the window the bug lived in.
  group('picking a file to plot', () {
    testWidgets('opens one dialog for two presses', (tester) async {
      final browsing = Completer<void>();
      final picker = _ParkedPicker(browsing);
      FilePicker.platform = picker;
      final (device, _) = mountedDevice();

      await tester.pumpWidget(wrapWithDevice(const PulsePlotterPage(), device));
      await tester.pumpAndSettle();

      // No pump between the taps. With one, the rebuild lands and the button
      // is already disabled, so the second tap is refused by the enabled
      // condition and the handler's own guard is never asked - which is how
      // this test first passed with that guard deleted.
      final open = find.byTooltip('Open signal file');
      await tester.tap(open);
      await tester.tap(open);
      await tester.pump();

      expect(picker.opened, 1);

      browsing.complete();
      await tester.pumpAndSettle();
      await closeDevice(tester, device);
    });
  });

  // A ratchet in ADR 0004's sense, and deliberately narrow: that the guard is
  // still *there*, counted and anchored so an inverted one fails too. What
  // notices a push site that never had a guard is
  // test/navigator_push_budget_test.dart, which counts the mechanism per area
  // instead of the fix per file - the first version of this list went green
  // with three unguarded sites in lib/, two of them in a file the same commit
  // edited.
  //
  // A site legitimately rewritten belongs off these lists, in the same commit.
  group('the sites whose whole handler is a push', () {
    const guarded = {
      'lib/pages/tools/infrared/brands_page.dart': 1,
      'lib/pages/tools/infrared/categories_page.dart': 2,
      'lib/pages/tools/infrared/page.dart': 1,
      'lib/pages/tools/paint/manager/page.dart': 1,
      'lib/pages/archive/overview/page.dart': 3,
      'lib/pages/flibler/project/page.dart': 1,
      'lib/pages/apps/catalog/page.dart': 1,
      'lib/pages/option/page.dart': 1,
    };
    final guard = RegExp(r'pushPage\(');

    test('all still push through the guarded helper', () {
      final counted = {
        for (final path in guarded.keys)
          path: guard.allMatches(io.File(path).readAsStringSync()).length,
      };

      expect(
        counted,
        guarded,
        reason: 'a tap handler went back to a bare Navigator.push (#244)',
      );
    });

    // The one site that asks the question itself rather than through
    // pushPage, because its handler is not only a push: the tool cards run an
    // `onTap` that may open a route some other way.
    test('the tool card list still asks before it opens anything', () {
      final source = io.File('lib/pages/tools/overview/page.dart')
          .readAsStringSync();

      expect(
        RegExp(r'if \(!isTopRoute\(context\)\) return;').allMatches(source),
        hasLength(1),
        reason: 'the tool cards lost or inverted their #244 guard',
      );
    });
  });

  // The other shape, where the guard is a flag or a keyed set rather than a
  // question to the navigator. Counted the same way as the list above, because
  // a file with the string twice and the guard once is the hole that list was
  // written to close.
  group('the sites that guard with a flag', () {
    const guards = {
      'lib/pages/apps/manager/install_page.dart': '_preparingSheet.add(',
      'lib/pages/tools/infrared/infrareds_page.dart': '_fetching.contains(',
      'lib/pages/tools/remote/desktop/page.dart':
          'if (_openingWristSettings) return;',
      'lib/pages/archive/overview/category/favorites_page.dart': 'ok == null',
      'lib/pages/archive/overview/page.dart': 'ok == null',
    };

    test('all still refuse a second entry', () {
      final missing = [
        for (final e in guards.entries)
          if (!io.File(e.key).readAsStringSync().contains(e.value)) e.key,
      ];

      expect(
        missing,
        isEmpty,
        reason:
            'a handler lost its #244 guard, or a caller stopped honouring the '
            'null that means "already under way"',
      );
    });
  });
}

/// A page whose button does what the guarded sites do: push, and nothing else.
///
/// Through `pushPage`, which is what those sites call now - so this exercises
/// the helper rather than a copy of what it does.
class _PushingPage extends StatelessWidget {
  const _PushingPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => pushPage(
          context,
          (_) => const Scaffold(body: Center(child: Text('pushed'))),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

/// A file picker held open for as long as the dialog would be.
class _ParkedPicker extends FilePicker {
  _ParkedPicker(this.browsing);

  final Completer<void> browsing;

  int opened = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    opened++;
    await browsing.future;
    // Nothing usable: the plot is not what this is about, and a null path is
    // the one outcome the page reports and then forgets.
    return FilePickerResult([PlatformFile(name: 'ir.ir', size: 0)]);
  }
}

/// A context that is never mounted, for the paths that only ask that.
class _DeadContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts the routes a navigator is actually given, which is what these
/// handlers are judged on. Only the pages pushed by the page under test: the
/// `home` route is pushed before this is attached.
class _CountingObserver extends NavigatorObserver {
  int count = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) count++;
  }
}
