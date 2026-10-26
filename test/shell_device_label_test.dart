import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/app.dart';
import 'package:qunleashed/app/nav_bar.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';
import 'package:qunleashed/pages/archive/overview/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/telemetry/settings.dart';

import 'archive_fakes.dart';
import 'firmware_fixture.dart';

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
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
  testWidgets('follows the archive from connected to syncing and back', (
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

    // One tag on the device and nothing on the phone, so the walk has a file
    // to fetch. Without it the sync lists ten empty category folders and
    // downloads nothing, which leaves the read half of the fake - and the
    // whole `storageReadChunked` path - unexercised, and makes "synced" a
    // weaker word than it looks.
    client.tree['/ext/nfc'] = [tag('badge.nfc')];
    client.bodies['/ext/nfc/badge.nfc'] =
        'Filetype: Flipper NFC device\nUID: 00 01 02 03\n';

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
    // `idle`, and it would leave `_deviceLabel`'s `synced` arm - the ternary
    // on `deviceInfoConnected` - asserted by nothing at all. This says which
    // end state the walk reached and which string that state draws.
    expect(archive.syncStatus.value, ArchiveSyncStatus.synced);
    expect(label(tester), l10n.deviceStateConnected);
    expect(
      client.requests,
      contains(contains('storageReadRequest')),
      reason:
          'the walk reached `synced` without fetching the one file on '
          'the card, so it was not a sync',
    );

    await closeDevice(tester, device);
  });
}

// ── What this does not pin ───────────────────────────────────────────────────
//
// Twenty mutations run across both new files, seventeen killed. The three
// recorded at the foot of `shell_rebuild_test.dart` that this file was written
// for all die - the `switch (_syncStatus)` dropped from `_deviceLabel`,
// `_syncStatus => idle`, and `syncStatus` dropped from the shell's merge - as
// do swapping either pair of arms in the label, each of the three
// `connectionState` guards, `isConnected => false`, the device taken off the
// connection event, a sync that never leaves `syncing`, the info patch
// published in line with the event, and the card left unseeded.
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
