import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/pages/archive/overview/category/deleted_page.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_fakes.dart';
import 'kept_lines.dart';

/// A bulk action that outlives the page it was started from.
///
/// QUNLEASHED-P. Every bulk action on the archive pages hands the selection's
/// exit to async code, so the page can be gone by the time it runs - and then
/// its `setState` reaches a disposed `State`. The guard lives inside
/// `ListSelection.exitSelection`, whose doc says why it is there rather than
/// at the call sites; four pages wrote that method out for themselves when this
/// file was written and all four share it now (#375).
///
/// **What this file holds is the reaching, not the guard.**
/// `list_selection_test.dart` fails the moment the `mounted` check goes; only
/// this one proves a real bulk action still hands the exit to async code at
/// all, which is the premise that check rests on.
///
/// **What fails here is not what a user saw.** In a release build `setState`
/// has no lifecycle assertion left and the null check on `_element`
/// (`framework.dart:1221`, the line in the report's own frame) is what throws,
/// as a fatal uncaught `TypeError`; under `flutter test` the framework's
/// "setState() called after dispose()" assertion fires first. Different
/// message, same call site, same mechanism - so this pins the defect even
/// though it cannot reproduce the exact exception the report carries.
///
/// The gate is `ArchiveRpcFake.writeGate`, which suspends
/// `callRpcFramesMulti` - what `storageWriteChunked` sends through - so the
/// restore stops at the longest of the three awaits that can outlive the page,
/// the read before it and the `refresh()` after it being the other two. The
/// seam is shared because it is the only one there is: the client's API is
/// extensions over a small core, so nothing above it can be faked (#376).
class _HangingFlipper with FlipperRpcFake, ArchiveRpcFake {
  /// Nothing on the device, which is what makes the local file read as
  /// deleted rather than synced.
  @override
  List<Main> framesFor(Main request) {
    if (!request.hasStorageListRequest()) return const [];
    return [Main(storageListResponse: ListResponse())];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  useTempArchiveRoot('archive_bulk_outlives');

  late _HangingFlipper client;

  /// Held until the case says the page is gone, through `writeGate`.
  late Completer<void> gate;
  late ArchiveController ctrl;

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
    gate = Completer<void>();
    client = _HangingFlipper()..writeGate = gate;
    refreshSettled = false;
  });

  /// A local NFC file with nothing answering for it on the device, which is
  /// `archive_partial_walk_test.dart`'s recipe for a key that reads as
  /// deleted.
  Future<void> pumpDeletedPage(WidgetTester tester) async {
    final mounted = await mountArchivePage(
      tester,
      client: client,
      seed: (storage) async {
        final dir = storage.categoryDir(archiveTestDevice, ArchiveCategory.nfc)
          ..createSync(recursive: true);
        io.File('${dir.path}${io.Platform.pathSeparator}card.nfc')
            .writeAsStringSync('Filetype: Flipper NFC device\n');
      },
      page: (controller, sortSettings) =>
          DeletedPage(controller: controller, sortSettings: sortSettings),
    );
    ctrl = mounted.controller;

    var sawLoading = false;
    ctrl.addListener(() {
      if (!client.writeSettled) return;
      if (ctrl.loading) {
        sawLoading = true;
      } else if (sawLoading) {
        refreshSettled = true;
      }
    });
  }

  /// Selects the one deleted key and taps Restore, leaving the restore
  /// suspended at the gate.
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
    gate.complete();
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
  /// stops at the write leaves `exitSelection` unreached, which is a test
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
    client.writeFailure = LinkDropped();
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
