import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/app/nav_bar.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/pages/archive/overview/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/telemetry/settings.dart';

import 'archive_fakes.dart';
import 'fake_device.dart';
import 'firmware_fixture.dart';
import 'view_size.dart';

/// The one string in the bottom bar, and what each of its six branches is read
/// from.
///
/// `_AppShellState._deviceLabel` is the only thing in the shell that depends on
/// either controller, which makes it the justification for both of them being
/// in the shell's merged listenable at all. Its `connected` branch is where all
/// the interesting reads are:
///
/// ```dart
/// case DeviceConnectionState.connected:
///   if (device.deviceLoading) return strings.deviceStateSyncing;
///   switch (_syncStatus) { ... }
/// ```
///
/// None of that was pinned before #413, because reaching it needs a device
/// the fixture could not supply - see `FakeFlipperClient`'s own doc.
/// (`shell_rebuild_test.dart` does assert the label *moves* on a device
/// notification, through the `recovering` branch, so it was this branch that
/// was unreachable rather than the label as a whole.) Three of the four
/// mutations recorded at the foot of that file die here.
///
/// **It takes the whole app**, not a fixture: the shell builds its own
/// `ArchiveController` from the client it was handed and keeps it private, so
/// the only way to move `syncStatus` is to make a real sync happen over a real
/// controller. That is also why the storage root is a temp directory here.
///
/// **The cases are not independent, and one line of this is why.** The info
/// patch `arriveWithDevice` publishes reaches `ArchiveController._setDeviceName`
/// too, which writes `.last_device` into that root - so from the second case
/// on, `initialize()` adopts `TestFlipper` before any device arrives. Harmless
/// for the cases below, which read the archive only once a device is connected,
/// but it is the hazard `useTempArchiveRoot`'s own header names and the next
/// case added here should know about it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useTempArchiveRoot('shell_label');

  setUp(resetFirmwareState);

  /// The whole app at a phone width, with a real device controller, settled.
  ///
  /// 360 rather than a desktop window because `FlipperRootScaffold` ignores
  /// `deviceLabel` entirely when `isWide` - the label this file is about is
  /// only drawn on the bottom bar. #407.
  ///
  /// `pumpAndSettle` is safe here and nowhere below: the two animations that
  /// repeat are both conditional - the file-list toolbar's spin and the
  /// progress button's - and neither is running with nothing connected and no
  /// sync in flight. Once a device arrives the archive's sync bar ticks for
  /// ever and a settle never returns, which is what `settle` is for.
  Future<(DeviceController, FakeFlipperClient)> pumpApp(
    WidgetTester tester,
  ) async {
    sizeView(tester, const Size(360, 900));

    final (device, client) = mountedDevice();
    await tester.pumpWidget(
      QUnleashedApp(
        client: client,
        diagnostics: DiagnosticsSettings(),
        permissions: PermissionCenter(),
        device: device,
      ),
    );
    await tester.pumpAndSettle();
    return (device, client);
  }

  String label(WidgetTester tester) => tester
      .widget<FlipperRootScaffold>(find.byType(FlipperRootScaffold))
      .deviceLabel;

  /// The archive controller the shell built, taken back out of the tree.
  ///
  /// Private to `_AppShellState` and handed to `ArchivePage`, which is in the
  /// tree from the first frame on a narrow layout: `_mounted` starts as
  /// `{device, archive, tools}` and `IndexedStack` builds every child.
  ///
  /// **`skipOffstage: false` is what finds it**, and the default does not -
  /// `shell_rebuild_test.dart`'s `showArchive` has the mechanism. Selecting
  /// the tab is the other way out of it; this way keeps the device tab on
  /// screen, which is where a user is when a sync starts behind them.
  ArchiveController archiveIn(WidgetTester tester) => tester
      .widget<ArchivePage>(find.byType(ArchivePage, skipOffstage: false))
      .controller;

  /// One tag on the device and nothing on the phone, so a sync has a file to
  /// fetch.
  ///
  /// Without it the sync lists ten empty category folders and downloads
  /// nothing, which leaves the read half of the fake - and the whole
  /// `storageReadChunked` path - unexercised, and makes "synced" a weaker
  /// word than it looks.
  ///
  /// [failing] makes that one read throw instead. It is the only way to a
  /// sync that *finishes* with something missing: a `bodies` entry that is
  /// absent reads as an empty file and saves perfectly well.
  void seedCard(FakeFlipperClient client, {bool failing = false}) {
    client.tree['/ext/nfc'] = [tag('badge.nfc')];
    client.bodies['/ext/nfc/badge.nfc'] =
        'Filetype: Flipper NFC device\nUID: 00 01 02 03\n';
    if (failing) client.readFailures.add('/ext/nfc/badge.nfc');
  }

  /// A full sync walked all the way to `synced`.
  ///
  /// Watching that walk is what the case below is about; the three after it
  /// need it to have happened and then test what is supposed to undo it, so
  /// they come through here. Both assertions on the way are load-bearing: a
  /// sync that never started, or one that ended on `idle`, would let a case
  /// about dropping `synced` pass without `synced` ever existing.
  Future<void> syncToSynced(
    WidgetTester tester,
    FakeFlipperClient client,
    ArchiveController archive,
  ) async {
    seedCard(client);
    unawaited(archive.syncAll());
    await tester.pump();
    expect(
      archive.syncStatus.value,
      ArchiveSyncStatus.syncing,
      reason: 'the sync never started',
    );
    await runUntil(
      tester,
      () => archive.syncStatus.value != ArchiveSyncStatus.syncing,
      reason: 'the sync never finished',
    );
    expect(
      archive.syncStatus.value,
      ArchiveSyncStatus.synced,
      reason: 'the sync did not reach `synced`, so nothing below is a drop',
    );
  }

  // ── The branches that need no archive ─────────────────────────────────────

  testWidgets('says there is no device before one arrives', (tester) async {
    final (device, _) = await pumpApp(tester);

    expect(label(tester), l10n.deviceStateNoDevice);

    await closeDevice(tester, device);
  });

  // The pair for the case above, and the one branch of the six that is
  // reachable *only* because of `arriveWithDevice`: `_deviceLabel` tells "no
  // device" from "disconnected" on `device.device != null` alone, so a link
  // that was never up and a link that dropped read differently - and until a
  // device could be held at all, only the first of those existed.
  testWidgets('says disconnected once a device has been seen', (tester) async {
    final (device, client) = await pumpApp(tester);

    client.arriveWithDevice();
    await settle(tester);
    client.stir();
    await settle(tester);

    expect(label(tester), l10n.deviceStateDisconnected);

    await closeDevice(tester, device);
  });

  testWidgets('says connecting while a link is being brought up', (
    tester,
  ) async {
    final (device, client) = await pumpApp(tester);

    client.connecting = true;
    client.stir();
    await settle(tester);

    expect(label(tester), l10n.deviceStateConnecting);

    await closeDevice(tester, device);
  });

  testWidgets('says DFU for a device in the bootloader', (tester) async {
    final (device, _) = await pumpApp(tester);

    device.setDfuPresent(true);
    await settle(tester);

    expect(label(tester), l10n.deviceStateDfu);

    await closeDevice(tester, device);
  });

  // Ahead of `isConnected` in `connectionState`, so this reads "recovering"
  // over a live link rather than instead of one.
  testWidgets('says recovering during a firmware recovery', (tester) async {
    final (device, client) = await pumpApp(tester);

    client.arriveWithDevice();
    await settle(tester);
    device.setRecovering(true);
    await settle(tester);

    expect(label(tester), l10n.deviceStateRecovering);

    await closeDevice(tester, device);
  });

  // ── The connected branch ──────────────────────────────────────────────────

  // The state a connection event alone leaves behind: `_ensureDataLoading`
  // sets `deviceLoading`, and on the stay-connected path nothing clears it but
  // a non-empty info patch - so the bar reads "syncing" before any archive
  // sync exists. This is the branch above the one the rest of the file is
  // about, and it has to be separated from it or "syncing" proves nothing.
  testWidgets('says syncing while the device info is still coming', (
    tester,
  ) async {
    final (device, client) = await pumpApp(tester);

    client.arriveWithDevice(info: const {});
    await settle(tester);

    expect(label(tester), l10n.deviceStateSyncing);

    await closeDevice(tester, device);
  });

  testWidgets('says connected once the device info has landed', (tester) async {
    final (device, client) = await pumpApp(tester);

    client.arriveWithDevice();
    await settle(tester);

    expect(label(tester), l10n.deviceStateConnected);

    await closeDevice(tester, device);
  });

  // **The case the fixture was built for.** Everything above reads off the
  // device controller alone; this is the only one that reads the archive's
  // `syncStatus`, and so the only witness in the suite for the archive
  // controller being in the shell's merged listenable.
  //
  // **What parks the sync at `syncing` is not a gate**, and a first draft of
  // this case held one on `callRpcFrames` in the belief that it was.
  // `storageList` goes through `callRpc`, so that gate was never awaited -
  // and the walk has not reached the client at all when the assertion runs.
  // What holds the status is `_syncAll` setting it and notifying before its
  // first await, so one `pump()` cannot miss it, and then the controller
  // waiting on its own file I/O, which the fake clock does not run. That last
  // is the fact `archive_fakes.dart`'s `runUntil` header is about.
  //
  // The status assertion beside the label is what makes that safe rather than
  // lucky: if the sync ever became fast enough to be over within the pump,
  // both halves fail together instead of the label quietly reading
  // "connected" for the right value at the wrong moment.
  testWidgets('follows the archive from connected through syncing to synced', (
    tester,
  ) async {
    final (device, client) = await pumpApp(tester);
    client.arriveWithDevice();
    await settle(tester);
    final archive = archiveIn(tester);
    expect(
      label(tester),
      l10n.deviceStateConnected,
      reason: 'the control: nothing is syncing yet',
    );

    seedCard(client);

    unawaited(archive.syncAll());
    await tester.pump();

    expect(
      label(tester),
      l10n.deviceStateSyncing,
      reason: 'the bar does not follow the archive controller at all',
    );
    expect(
      archive.syncStatus.value,
      ArchiveSyncStatus.syncing,
      reason:
          'the sync was over before the bar was read, so the line above '
          'proves nothing about the bar',
    );

    await runUntil(
      tester,
      () => archive.syncStatus.value != ArchiveSyncStatus.syncing,
      reason: 'the sync never finished',
    );

    // Not `isNot(syncing)`: that also passes for a sync that crashed into
    // `idle`, which draws `deviceStateConnected` - the string the bar was
    // already showing before the sync began, so the pair would hold for a
    // sync that failed. This says which end state the walk reached and which
    // string that state draws, and since #420 those are two different
    // strings - a finished sync is the only way to read `deviceStateSynced`
    // at all.
    expect(archive.syncStatus.value, ArchiveSyncStatus.synced);
    expect(label(tester), l10n.deviceStateSynced);
    expect(
      client.requests,
      contains(contains('storageReadRequest')),
      reason:
          'the walk reached `synced` without fetching the one file on '
          'the card, so it was not a sync',
    );

    await closeDevice(tester, device);
  });

  // ── What "Synced" does not claim ──────────────────────────────────────────
  //
  // Three cases for three ways the word would be a lie, and all three were
  // unobservable before #420 made the string reachable: `idle` and `synced`
  // drew the same label, so each of the mechanisms below could be deleted
  // and the whole suite stayed green. Two of them were, to check.

  // A sync that finished with a file missing is not a synced archive, and the
  // difference is one check in `_syncAll` - `_lastError == null ? synced :
  // idle`. Collapsing that ternary to `synced` survives every other test in
  // `test/`, because nothing else reads the status at all.
  testWidgets('does not say synced when a file failed to come down', (
    tester,
  ) async {
    final (device, client) = await pumpApp(tester);
    client.arriveWithDevice();
    await settle(tester);
    final archive = archiveIn(tester);
    seedCard(client, failing: true);

    unawaited(archive.syncAll());
    await tester.pump();
    expect(
      archive.syncStatus.value,
      ArchiveSyncStatus.syncing,
      reason: 'the sync never started',
    );
    await runUntil(
      tester,
      () => archive.syncStatus.value != ArchiveSyncStatus.syncing,
      reason: 'the sync never finished',
    );

    expect(archive.syncStatus.value, ArchiveSyncStatus.idle);
    expect(
      archive.lastError,
      isNotNull,
      reason: 'the read was answered after all, so the sync did not fail',
    );
    expect(label(tester), l10n.deviceStateConnected);

    await closeDevice(tester, device);
  });

  // The link going away is what `ArchiveController._onConnectionChange` has
  // always reset the status for. The reconnect at the end is the half worth
  // having: it says the status comes back as `idle` and not as whatever the
  // previous session earned.
  testWidgets('drops synced when the link goes down', (tester) async {
    final (device, client) = await pumpApp(tester);
    client.arriveWithDevice();
    await settle(tester);
    final archive = archiveIn(tester);
    await syncToSynced(tester, client, archive);

    client.depart();
    client.stir();
    await settle(tester);

    expect(archive.syncStatus.value, ArchiveSyncStatus.idle);
    expect(label(tester), l10n.deviceStateDisconnected);

    client.arriveWithDevice();
    await settle(tester);

    expect(label(tester), l10n.deviceStateConnected);

    await closeDevice(tester, device);
  });

  // **The swap, which is not a disconnect.** Activating a session that is
  // already connected - a tap on a held entry in the connection list - emits
  // one connected event carrying the other device and nothing in between, so
  // a status keyed on connected-ness alone survives it and the bar reads
  // "Synced" about a card this app has never opened. #420 made that visible;
  // `_onConnectionChange` keys on the device id for it.
  testWidgets('drops synced when another Flipper takes the front', (
    tester,
  ) async {
    final (device, client) = await pumpApp(tester);
    client.arriveWithDevice();
    await settle(tester);
    final archive = archiveIn(tester);
    await syncToSynced(tester, client, archive);

    client.arriveWithDevice(
      device: flipperDevice('second', 'OtherFlipper'),
      info: const {
        'hardware_name': 'OtherFlipper',
        'firmware_version': '1.3.4',
      },
    );
    await settle(tester);

    expect(archive.syncStatus.value, ArchiveSyncStatus.idle);
    expect(label(tester), l10n.deviceStateConnected);

    await closeDevice(tester, device);
  });

  // One category in step is not the archive in step, and the status is one
  // word about the whole of it. `_syncCategory` used to promote to `synced`
  // like `_syncAll` - reachable from a category page's pull-to-refresh, so a
  // refresh of Sub-GHz alone claimed the lot.
  testWidgets('does not say synced for one category', (tester) async {
    final (device, client) = await pumpApp(tester);
    client.arriveWithDevice();
    await settle(tester);
    final archive = archiveIn(tester);
    seedCard(client);

    unawaited(archive.syncCategory(ArchiveCategory.nfc));
    await tester.pump();
    expect(
      archive.syncStatus.value,
      ArchiveSyncStatus.syncing,
      reason: 'the category sync never started',
    );
    await runUntil(
      tester,
      () => archive.syncStatus.value != ArchiveSyncStatus.syncing,
      reason: 'the category sync never finished',
    );

    expect(archive.syncStatus.value, ArchiveSyncStatus.idle);
    expect(label(tester), l10n.deviceStateConnected);
    expect(
      client.requests,
      contains(contains('storageReadRequest')),
      reason: 'the category walk fetched nothing, so it synced nothing',
    );

    await closeDevice(tester, device);
  });
}

// ── What this does not pin ───────────────────────────────────────────────────
//
// Twenty mutations run across both new files when they were written,
// seventeen killed. **#420 added six more, all six killed**, each by the one
// case named for it:
//
//  * `synced` drawing `deviceStateConnected`, the behaviour it replaced;
//  * `idle` drawing `deviceStateSynced`;
//  * `_syncAll` reaching `synced` with `_lastError` set;
//  * `_syncCategory` promoting to `synced`, as it used to;
//  * `_onConnectionChange` not resetting the status at all;
//  * `_onConnectionChange` keyed on connected-ness rather than on which
//    device is in front - killed by the swap case **alone**, which is the
//    whole reason that case is separate from the link-down one.
//
// Two on code #420 did not touch were re-run, and both still die: the
// `deviceLoading` early return dropped, and the no-device/disconnected
// ternary inverted.
//
// Of the original twenty, the three recorded at the foot of
// `shell_rebuild_test.dart` that this file was written for all die - the
// `switch (_syncStatus)` dropped from `_deviceLabel`, `_syncStatus => idle`,
// and `syncStatus` dropped from the shell's merge - as do each of the three
// `connectionState` guards, `isConnected => false`, the device taken off the
// connection event, a sync that never leaves `syncing`, the info patch
// published in line with the event, and the card left unseeded. That list is
// not the whole twenty: the count is the record, not the enumeration.
//
// Three survive:
//
//  * **a `notifyListeners()` beside the status notifier's assignment.** It
//    notifies more, not less, so nothing that reads a value can see it. The
//    note in `shell_rebuild_test.dart` has what would.
//  * **dropping the snapshot accumulation from [FakeFlipperClient.publish].**
//    Every card here is built before a patch arrives, so they all read it off
//    the stream; the accumulation is fidelity to the real session rather than
//    something a case depends on.
//  * **`DeviceScope.notifierOf` swapped for the listening `of` in
//    `_openFullInfo`.** `device_full_info_test.dart`'s header says why that
//    one is out of reach here.
