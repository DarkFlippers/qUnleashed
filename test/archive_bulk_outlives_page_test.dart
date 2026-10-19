import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/pages/archive/overview/category/deleted_page.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/archive/sort_settings.dart';
import 'package:qunleashed/services/archive/storage.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_fakes.dart';
import 'kept_lines.dart';

/// A bulk action that outlives the page it was started from.
///
/// QUNLEASHED-P. Every bulk action on the archive pages hands `_exitSelection`
/// to async code, so the page can be gone by the time it runs - and then its
/// `setState` reaches a disposed `State`. The guard is inside `_exitSelection`
/// itself rather than at the call sites, because the call sites are the part
/// that was forgotten: four of the five that needed it already had a `mounted`
/// check one statement away, around the toast beside the exit.
///
/// **What fails here is not what a user saw.** In a release build `setState`
/// has no lifecycle assertion left and the null check on `_element`
/// (`framework.dart:1221`, the line in the report's own frame) is what throws,
/// as a fatal uncaught `TypeError`; under `flutter test` the framework's
/// "setState() called after dispose()" assertion fires first. Different
/// message, same call site, same mechanism - so this pins the defect even
/// though it cannot reproduce the exact exception the report carries.
///
/// The gate is `callRpcFramesMulti`, which is what `storageWriteChunked` sends
/// through, so the restore is suspended at the longest of the three awaits
/// that can outlive the page - the read before it and the `refresh()` after it
/// being the other two.
class _HangingFlipper with ArchiveRpcFake {
  /// Held until the test says the page is gone.
  final Completer<void> gate = Completer<void>();

  /// Makes the write throw once the gate is let go, for the case about what a
  /// failure leaves behind. [LinkDropped] is `archive_fakes.dart`'s shared
  /// stand-in; `ArchiveRpcFake.isLinkDropError` answers false for it unless a
  /// fake says otherwise, so the restore does not retry and the throw lands in
  /// `_restoreKeys`'s catch, which is the path under test.
  bool failWrite = false;

  /// Whether the restore got as far as the write at all. Asserted, because a
  /// gate nothing reaches would make this file pass against any code.
  bool writeStarted = false;

  /// Whether the write has returned or thrown. Asserted for the same reason:
  /// a restore that never resumed cannot have reached the line under test.
  bool writeSettled = false;

  /// Nothing on the device, which is what makes the local file read as
  /// deleted rather than synced.
  @override
  List<Main> framesFor(Main request) {
    if (!request.hasStorageListRequest()) return const [];
    return [Main(storageListResponse: ListResponse())];
  }

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    writeStarted = true;
    try {
      await gate.future;
      if (failWrite) throw LinkDropped();
      await send((_) async {});
      return const [];
    } finally {
      writeSettled = true;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Interleaved real-clock steps a restore is given to finish.
///
/// Not a measured margin: the live-page case below is what certifies it,
/// because that one fails if the budget is too short for the continuation to
/// run. Sized so a stall costs a couple of seconds rather than the suite's
/// ten-minute timeout.
const int _budget = 200;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  useTempArchiveRoot('archive_bulk_outlives');

  late _HangingFlipper client;
  late ArchiveController ctrl;
  late ArchiveSortSettings settings;

  /// True once the `refresh()` that `_restoreKeys` ends with has finished, so
  /// `restoreKeys` has completed and the page's continuation - the line under
  /// test - is one microtask away.
  ///
  /// This is the only thing still observable after the page is gone, and it is
  /// what stops this file waiting out a fixed budget on every run. Gated on
  /// `writeSettled` so the `notifyListeners()` that `_restoreKeys` makes
  /// *before* the refresh cannot answer for it.
  late bool refreshSettled;

  setUp(() {
    clearKeptLines();
    SharedPreferences.setMockInitialValues(const {});
    client = _HangingFlipper();
    settings = ArchiveSortSettings();
    refreshSettled = false;
  });

  /// Bounded pumps. `pumpAndSettle` does not return on these pages, and the
  /// gate below is deliberately never settled.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Runs the real clock until [done], which is the only way the restore gets
  /// past any of its awaits.
  ///
  /// `_restoreKeys` reads the file off disk before it writes, and `testWidgets`
  /// drives a fake clock that does not run real file I/O to completion - so
  /// without this the restore suspends at the read and never reaches the gate.
  /// The `pump` inside the loop is load-bearing and not a tidy-up: the
  /// controller's flow needs the fake clock advanced between real-clock
  /// slices, and a single `runAsync` with a poll inside it never completes.
  /// Bounded rather than a bare `while`: a condition that never comes true
  /// should fail this file in seconds, not hang it until the timeout.
  Future<void> runUntil(
    WidgetTester tester,
    bool Function() done, {
    required String reason,
  }) async {
    for (var i = 0; i < _budget && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: reason);
  }

  /// A local NFC file with nothing answering for it on the device, which is
  /// `archive_partial_walk_test.dart`'s recipe for a key that reads as
  /// deleted.
  Future<void> pumpDeletedPage(WidgetTester tester) async {
    final storage = ArchiveStorage();
    await tester.runAsync(() async {
      await storage.resolveRootDir();
      final device = storage.deviceDir(archiveTestDevice);
      if (device.existsSync()) device.deleteSync(recursive: true);
      await storage.writeLastDeviceName(archiveTestDevice);
      final dir = storage.categoryDir(archiveTestDevice, ArchiveCategory.nfc)
        ..createSync(recursive: true);
      io.File('${dir.path}${io.Platform.pathSeparator}card.nfc')
          .writeAsStringSync('Filetype: Flipper NFC device\n');
      ctrl = ArchiveController(client: client, storage: storage);
      await ctrl.initialize();
      await settings.load();
    });

    var sawLoading = false;
    ctrl.addListener(() {
      if (!client.writeSettled) return;
      if (ctrl.loading) {
        sawLoading = true;
      } else if (sawLoading) {
        refreshSettled = true;
      }
    });

    addTearDown(() async {
      ctrl.dispose();
      settings.dispose();
      await client.close();
    });

    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
        home: DeletedPage(controller: ctrl, sortSettings: settings),
      ),
    );
    await settle(tester);
  }

  /// Selects the one deleted key and taps Restore, leaving the restore
  /// suspended at [_HangingFlipper.gate].
  Future<void> startRestore(WidgetTester tester) async {
    expect(find.text('card'), findsOneWidget);

    await tester.longPress(find.text('card'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settle(tester);

    await tester.tap(find.text('Restore'));
    await settle(tester);

    await runUntil(
      tester,
      () => client.writeStarted,
      reason: 'the restore never reached the write, so nothing is suspended',
    );
  }

  /// Lets the gate go and waits for `restoreKeys` to complete.
  Future<void> finishRestore(WidgetTester tester) async {
    client.gate.complete();
    await runUntil(
      tester,
      () => refreshSettled,
      reason:
          'the restore never got past refresh(), so the exit was never '
          'reached and this case proves nothing',
    );
    await settle(tester);
  }

  /// The restore finishing while the page is still up.
  ///
  /// Here to keep the cases below honest. `_restoreKeys` ends in a `refresh()`,
  /// so the write returning is not the continuation running - and a wait that
  /// stops at the write leaves `_exitSelection` unreached, which is a test
  /// that passes against the defect. The first version of this file did
  /// exactly that. This case asserts the one thing the continuation does that
  /// can be seen, so it fails if the wait is too short.
  testWidgets('a restore that finishes on a live page clears the selection', (
    tester,
  ) async {
    await pumpDeletedPage(tester);
    await startRestore(tester);

    expect(
      find.byIcon(Icons.more_horiz_rounded),
      findsOneWidget,
      reason: 'the selection toolbar should still be up mid-restore',
    );

    await finishRestore(tester);

    expect(
      find.byIcon(Icons.more_horiz_rounded),
      findsNothing,
      reason: 'the continuation ran but did not clear the selection',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restore that finishes after the page is gone says nothing', (
    tester,
  ) async {
    await pumpDeletedPage(tester);
    await startRestore(tester);

    // The page goes while the write is still held.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await settle(tester);
    // The case's own premise. If the page ever survived the swap this would
    // quietly take the live path above and pass for that reason.
    expect(find.byType(DeletedPage), findsNothing);

    await finishRestore(tester);

    expect(
      client.writeSettled,
      isTrue,
      reason: 'the write never returned, so the continuation never ran',
    );
    // `takeException` is the stated assertion but not the detector: an
    // unhandled rejection reaching the zone ends the test from
    // `handleUncaughtError` before this line runs. What it does catch is the
    // day somebody wraps the call site in `guarded()`, which by contract
    // never rejects - then the throw arrives here as a kept error line
    // instead, which is what the second expect is for.
    expect(tester.takeException(), isNull);
    expect(keptLevels, isNot(contains(KeptLevel.error)));
  });

  /// What the guard does *not* cost, which is the other half of the claim the
  /// production comment makes ("nothing is lost by returning early").
  ///
  /// A restore that fails after the user leaves still has to leave a record,
  /// and the toast is not it - that was already behind a `mounted` check
  /// before this change. `ArchiveController._restoreKeys`'s catch is, at a
  /// level release builds keep.
  testWidgets('a restore that fails after the page is gone is still recorded', (
    tester,
  ) async {
    client.failWrite = true;
    await pumpDeletedPage(tester);
    await startRestore(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await settle(tester);

    await finishRestore(tester);

    // `contains`, not `hasLength(1)`: `LogService` folds a consecutive
    // identical body, so a count cannot tell "said once" from "said twice".
    expect(
      keptLines,
      contains(contains('[Archive] restore card.nfc failed')),
      reason: 'a restore that failed with the page gone reached no record',
    );
    expect(keptLevels, contains(KeptLevel.warning));
    expect(tester.takeException(), isNull);
  });
}
