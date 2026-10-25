import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
// Not exported by the package root, and `FlipperClient` declares `transport`,
// so this mixin has to name the type to answer it.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/sort_settings.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/storage/paths.dart';
import 'package:qunleashed/theme/theme.dart';

/// The RPC plumbing every archive fake needs, so only the answers differ.
///
/// Shared rather than copied, for the reason `fake_app_client.dart`'s header
/// gives about its own subject: the archive controller reaches the device
/// through `storageList` and `storageReadChunked`, both of which are
/// `extension ... on FlipperClient` and resolved **statically** - so declaring
/// them on a fake does nothing and every test has to fake `callRpcFrames` and
/// `callRpc` underneath them instead. That is ~90 lines of identical
/// boilerplate, and three files carried it before this was pulled out.
///
/// A class that mixes this in implements [framesFor] and nothing else; it can
/// still declare any member here itself and its own wins. It also needs its
/// own `noSuchMethod`, which is what lets the rest of `FlipperClient` go
/// unimplemented - a mixin cannot supply that for its users.
mixin ArchiveRpcFake implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();
  final _info = StreamController<Map<String, String>>.broadcast();

  /// Suspends the write until it is completed, when a fake sets one.
  ///
  /// Opt-in: null is "answer the write at once", which is what every fake here
  /// did before this existed. [callRpcFramesMulti] is the seam for it because
  /// it is the one `storageWriteChunked` sends through - CLAUDE.md's rule that
  /// the client's API is extensions over a small core is what makes it the
  /// only one - so a test about something outliving an upload or a restore
  /// holds it here and nowhere else.
  Completer<void>? writeGate;

  /// Thrown from the write once [writeGate] is let go, when a fake sets one.
  ///
  /// [LinkDropped] is the stand-in to reach for: [isLinkDropError] answers
  /// false for it unless a fake says otherwise, so the operation does not
  /// retry and the throw lands in the caller's own catch.
  Object? writeFailure;

  /// How many writes have been started, and how many have returned or thrown.
  ///
  /// Worth asserting in any case that gates one: a gate nothing reaches, or a
  /// continuation that never ran, would make the case pass against any code -
  /// which is why these are read-only. A case that could write
  /// `client.writeStarted = true` could satisfy its own `runUntil` and pass
  /// against anything, and that is the failure CLAUDE.md warns about by name.
  ///
  /// Counts rather than flags behind the two getters, so the day a case has
  /// to tell one write from another the number is already there. Both getters
  /// read "any write", which is the honest reading of a count above zero.
  int _started = 0;
  int _settled = 0;

  bool get writeStarted => _started > 0;
  bool get writeSettled => _settled > 0;

  /// The frames a request is answered with, or a throw for a request that
  /// fails. The one thing each fake decides for itself.
  List<Main> framesFor(Main request);

  Future<void> close() async {
    await _connection.close();
    await _info.close();
  }

  /// `initialize()` subscribes to both before its first refresh. Broadcast and
  /// never pushed to: a stream that ended would report `hasListener` false to
  /// anything that looks, and `connectionStream` is documented as a broadcast
  /// stream an error does not end.
  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _info.stream;

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  String? getName() => archiveTestDevice;

  @override
  Future<String> awaitName() async => archiveTestDevice;

  /// Read off the client by `storageWriteChunked` to size its frames, so any
  /// fake on an upload path has to answer it. Null is what every archive fake
  /// answered by hand before this moved here.
  @override
  Transport? get transport => null;

  /// False unless a fake says otherwise - `archive_sync_link_drop_test.dart`
  /// is the one that does, and a declaration on the class wins over this.
  @override
  bool isLinkDropError(Object e) => false;

  /// Whatever [isConnected] says, which for a fake that never moves is the
  /// honest answer: a fake with a dead link that forgot to override this
  /// would otherwise be told the link came back, and pass for that reason.
  ///
  /// Three waiters reach this through the mixin - the sync loop's retry, the
  /// delete loop's link check, and flipperlib's own upload restart
  /// (`client/api/storage.dart`). The third is dormant here only because
  /// [isLinkDropError] above answers false, which is worth knowing before
  /// relying on the count.
  @override
  Future<bool> waitForRpcSession(Duration timeout) async => isConnected;

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  /// Pumps the sender once and answers nothing, which is every current fake's
  /// behaviour: the write path calls it, and no test asserts on the frames it
  /// sends back.
  ///
  /// [writeGate] and [writeFailure] are the two things a fake can change about
  /// that, and both are null by default.
  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    _started++;
    try {
      await writeGate?.future;
      final failure = writeFailure;
      if (failure != null) throw failure;
      await send((_) async {});
      return const [];
    } finally {
      _settled++;
    }
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
    final frames = framesFor(request);
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
    final frames = framesFor(request);
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
}

/// The device name every archive fake answers with, and the folder the tests'
/// local files land in.
const String archiveTestDevice = 'TestFlipper';

/// A link that died, as the app's own classifier recognises it.
///
/// A stand-in for `FlipperTransportError` and the four `StateError` spellings
/// `FlipperClient.isLinkDropError` matches: a fake overrides that to test for
/// this type, so the real substring list is not duplicated into a test. Shared
/// because the read and the write halves of the same link-drop restart policy
/// are tested in different files and should not disagree about what a drop is.
class LinkDropped implements Exception {
  @override
  String toString() => 'Bad state: Request dropped';
}

fl.File dir(String name) => fl.File(name: name, type: File_FileType.DIR);

fl.File tag(String name, {int size = 64}) =>
    fl.File(name: name, type: File_FileType.FILE, size: size);

/// A device whose storage holds one file, `notes.txt`, and nothing else.
///
/// Enough to mount `FileManagerPage` and see that it is still standing, which
/// is what the two pick tests need it for - `unguarded_pick_test.dart` for a
/// refused pick and `dropped_pick_test.dart` for one that came back empty.
///
/// Shared at the second file rather than the third, which is not what
/// `ratchet.dart`'s rule says and is not that rule's subject either: it is
/// about extracting a *predicate* two ratchets happen to agree on today, where
/// pulling it out early fixes the wrong shape. This is a fixture, and two
/// copies of a fake whose `framesFor` has to match a submodule's signatures
/// drift silently - which is the argument the mixin above it was extracted on.
class ListingFlipper with ArchiveRpcFake {
  @override
  List<Main> framesFor(Main request) => request.hasStorageListRequest()
      ? [Main(storageListResponse: ListResponse()..file.add(tag('notes.txt')))]
      : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Bounded pumps, for a page `pumpAndSettle` does not return on.
///
/// Every archive page keeps the sync bar's animation ticking, so a settle
/// waits out the suite's timeout instead of returning. One pump for the frame
/// and one for the toolbars' animation is what the files doing this by hand
/// had each arrived at.
///
/// The `DeviceScope` poll above the page used to be named here as a second
/// source. Its timer still runs, but no archive page depends on the scope
/// since #344, so it no longer rebuilds one.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Interleaves real-clock slices with pumps until [done], or fails saying
/// [reason].
///
/// **The `pump` inside the loop is load-bearing and not a tidy-up.** Anything
/// the archive controller does to disk is real file I/O, which `testWidgets`'
/// fake clock does not run to completion - so it needs [WidgetTester.runAsync]
/// - while its own flow needs the fake clock advanced between those slices, so
/// a single `runAsync` with a poll inside it never completes. That fact about
/// `flutter_test` is why this is here rather than in the one file that first
/// needed it: every archive test that waits on real I/O has to know it.
///
/// Bounded rather than a bare `while`: a condition that never comes true
/// should fail in seconds rather than hang until the ten-minute timeout.
/// [steps] is not a measured margin - the live-page case in
/// `archive_bulk_outlives_page_test.dart` is what certifies it, because that
/// one fails if the budget is too short for the continuation to run.
Future<void> runUntil(
  WidgetTester tester,
  bool Function() done, {
  required String reason,
  int steps = 200,
}) async {
  for (var i = 0; i < steps && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: reason);
}

/// What [mountArchivePage] built, for a case that has to reach past the page.
///
/// No storage: [mountArchivePage] hands that to `seed`, which is the only
/// thing that wants it.
typedef MountedArchive = ({
  ArchiveController controller,
  ArchiveSortSettings sortSettings,
});

/// Brings up an archive controller over [client] and pumps [page] on it.
///
/// Written out by hand, with small differences, in every archive test that
/// pumped a page (#376). The disk half alone is still hand-written where no
/// page is mounted - `archive_partial_walk_test.dart` and
/// `archive_sync_link_drop_test.dart`. It runs inside [WidgetTester.runAsync]
/// for the reason [runUntil] gives, and a test that skips that hangs at
/// `initialize()` until the timeout rather than failing.
///
/// [seed] is what each case differs in: it is handed the storage with the root
/// resolved, the device folder wiped and the device name written, so it can
/// write the local files or favourites the page is supposed to show. The
/// controller is built after it returns, so anything seeded is there for the
/// first refresh.
///
/// The controller, the settings and [client] are closed from `addTearDown`;
/// the surface size is set and restored the same way. `SharedPreferences`
/// stays with the caller - the sort settings read it, and whether a case wants
/// mock values or not is the case's business.
Future<MountedArchive> mountArchivePage(
  WidgetTester tester, {
  required ArchiveRpcFake client,
  required Widget Function(
    ArchiveController controller,
    ArchiveSortSettings sortSettings,
  )
  page,
  Future<void> Function(ArchiveStorage storage)? seed,
}) async {
  final storage = ArchiveStorage();
  final settings = ArchiveSortSettings();
  late ArchiveController controller;
  await tester.runAsync(() async {
    await storage.resolveRootDir();
    final device = storage.deviceDir(archiveTestDevice);
    if (device.existsSync()) device.deleteSync(recursive: true);
    await storage.writeLastDeviceName(archiveTestDevice);
    await seed?.call(storage);
    controller = ArchiveController(client: client, storage: storage);
    await controller.initialize();
    await settings.load();
  });

  addTearDown(() async {
    controller.dispose();
    settings.dispose();
    await client.close();
  });

  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
      home: page(controller, settings),
    ),
  );
  await settle(tester);
  return (controller: controller, sortSettings: settings);
}

/// Points `ArchiveStorage` at a fresh temp directory for the file, and
/// answers the `path_provider` call the pre-Devices migration makes.
///
/// Registers its own `setUpAll`/`tearDownAll`, so a file calls it once at the
/// top of `main()`. `ArchiveStorage` caches its root in a static, which is
/// why the root is per file rather than per case; rebuild the device folder
/// in `setUp` if cases must not see each other's files.
///
/// Shared for the reason this file exists at all: the same twenty lines, down
/// to the comment explaining the mock, were in three test files. The
/// migration runs at the top of every refresh and asks `path_provider` where
/// the old folders were - unanswered it throws, and the whole refresh ends in
/// the catch below it, which reads as an empty archive rather than an error.
io.Directory useTempArchiveRoot(String prefix) {
  final root = io.Directory.systemTemp.createTempSync(prefix);
  setUpAll(() {
    debugUseDocumentsRoot(root);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '${root.path}${io.Platform.pathSeparator}legacy',
        );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    debugUseDocumentsRoot(null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return root;
}
