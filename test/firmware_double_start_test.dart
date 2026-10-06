import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/progress_button.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/source.dart';
import 'package:qunleashed/pages/devices/firmware/update_state.dart';
import 'package:qunleashed/pages/devices/firmware/update_tracker.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_update_button.dart';

import 'firmware_fixture.dart';

/// Starting a firmware update twice.
///
/// The button had a re-entrancy guard, `_inProgress` - but that is derived from
/// the update tracker, and the tracker only learns about an update at
/// `_tracker.publish()`. On the custom-archive branch that call sits *after* an
/// await on a native file picker, so for the picker's whole lifetime the button
/// was still enabled and the handler re-entrant. Two picks meant two concurrent
/// `FirmwareInstaller.install` calls, interleaving `storageWriteChunked` into
/// the same `/ext/update/<dir>` and issuing two `runUpdate` commands - the worst
/// payload of any double-tap in the app (#244).
///
/// It has to be the custom branch. The remote branch reaches `publish()` with no
/// await in between, so `_inProgress` already covered it - a first draft of this
/// drove the remote path and passed with the fix reverted, proving nothing.
class _ParkedPicker extends FilePicker {
  _ParkedPicker(this.chosen, this.browsing);

  /// The path the user eventually picks.
  final String chosen;

  /// Held open for as long as the dialog would be, which is the window the bug
  /// lived in.
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
    return FilePickerResult([
      PlatformFile(path: chosen, name: 'fw.tgz', size: 1),
    ]);
  }
}

void main() {
  group('starting a custom firmware update', () {
    late DeviceController device;
    late FakeFlipperClient client;

    setUp(() {
      (device, client) = mountedDevice();
      client.arriveQuietly();
      addTearDown(() {
        // FirmwareUpdateTracker is a process-wide singleton, so a state left by
        // one case disables the button in the next - the guard under test reads
        // _inProgress, which is derived from it.
        FirmwareUpdateTracker.instance.clear(client.scopedDeviceId);
      });
    });

    /// Installs a picker that stays open until [browsing] completes.
    ///
    /// [browsing] has to be created inside the test body, never in `setUp`: a
    /// Completer built outside testWidgets' FakeAsync zone delivers its
    /// continuations to the real event loop, so completing it from the body
    /// resumes the dialog only *after* the body has finished - and every
    /// assertion in between reads a state that has not happened yet.
    _ParkedPicker park(Completer<void> browsing) {
      final picker = _ParkedPicker('C:/tmp/fw.tgz', browsing);
      FilePicker.platform = picker;
      return picker;
    }

    Widget button({
      required Future<UpdateState> Function({
        required FirmwareSource source,
        required FlipperClient client,
        required void Function(UpdateState) onState,
      })
      install,
    }) => wrapWithDevice(
      FirmwareUpdateButton(
        entry: unleashed,
        fetchState: FirmwareFetchState.ready,
        latestVersion: '1.0.0',
        deviceVersion: '0.9.0',
        deviceInfo: const {},
        // The branch with the gap.
        selectedChannelId: kCustomFirmwareChannelId,
        selectedVariant: UnleashedVariant.extraPacks,
        client: client,
        install: install,
      ),
      device,
    );

    testWidgets('twice in one gesture opens one picker and installs once', (
      tester,
    ) async {
      final browsing = Completer<void>();
      final picker = park(browsing);
      var installs = 0;
      await tester.pumpWidget(
        button(
          install:
              ({required source, required client, required onState}) async {
                installs++;
                onState(const UpdateDone());
                return const UpdateDone();
              },
        ),
      );
      await tester.pump();

      final target = find.byType(ProgressButton);
      // Two taps in one frame: a desktop double click is one gesture as far as
      // the user is concerned.
      await tester.tap(target);
      await tester.tap(target);
      await tester.pump();

      expect(
        picker.opened,
        1,
        reason:
            'the second press must be refused while the dialog is open - '
            'this is the window _inProgress could not see',
      );
      // The handler guard alone stops the double install; this pins the other
      // half, so the button also *looks* refused rather than taking a click
      // that quietly does nothing.
      expect(
        tester.widget<ProgressButton>(target).onPressed,
        isNull,
        reason: 'and the button shows it is refused while the dialog is open',
      );

      // Carried through to the install, because the picker count is only a
      // proxy for it: a custom branch that picked an archive and then never
      // flashed it - this whole feature deleted - left both assertions above
      // green.
      browsing.complete();
      await tester.pumpAndSettle();
      expect(installs, 1, reason: 'one dialog, one archive, one install');
    });

    // The other half of the guard, and the half a test that only parks the
    // dialog cannot see: `_starting` is released in a `finally`, and nothing
    // above ever runs it. Emptying that `finally` - or clearing the flag
    // without a setState, so the button stays drawn disabled - leaves the
    // primary action dead for the rest of the session after one press, which is
    // worse than the double start it replaced.
    //
    // Driven through a failing install, because that is the path where pressing
    // again is the whole of what the user can do.
    testWidgets('and is pressable again once the attempt is over', (
      tester,
    ) async {
      final browsing = Completer<void>();
      final picker = park(browsing);
      var installs = 0;
      await tester.pumpWidget(
        button(
          install:
              ({required source, required client, required onState}) async {
                installs++;
                // What an unwritable staging directory arrives as: outside
                // FirmwareInstaller's own try, so the widget's catch handles
                // it.
                throw StateError('could not create the staging directory');
              },
        ),
      );
      await tester.pump();

      final target = find.byType(ProgressButton);
      await tester.tap(target);
      await tester.pump();
      expect(picker.opened, 1, reason: 'the dialog is up');

      // The user picks, the install fails, the widget reports it.
      browsing.complete();
      await tester.pumpAndSettle();
      expect(installs, 1);
      expect(
        tester.widget<ProgressButton>(target).onPressed,
        isNotNull,
        reason: 'a failed attempt has to leave the button pressable',
      );

      // Past the six-second error toast, which covers the button: a tap landing
      // on it would make this read as a latched guard. It also drains the
      // toast's timer, which a widget test fails on if left pending.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      await tester.tap(target);
      await tester.pump();
      expect(
        picker.opened,
        2,
        reason: 'and pressing it has to open the dialog a second time',
      );
    });

    // The dialog is modal to the OS, not to Flutter, so the page behind it can
    // be navigated away while it is open. Without the mounted check after the
    // pick, setState throws from an async gap and the flash starts anyway with
    // nothing on screen to report it.
    //
    // Its own case on purpose: this was covered only as a side effect of the
    // teardown completing the dialog after the tree was gone, so the coverage
    // was accidental, arrived as an unattributed zone error after every
    // assertion had already passed, and would have vanished the moment the
    // teardown changed.
    testWidgets('an archive chosen after the page has gone is not flashed', (
      tester,
    ) async {
      final browsing = Completer<void>();
      park(browsing);
      var installs = 0;
      await tester.pumpWidget(
        button(
          install:
              ({required source, required client, required onState}) async {
                installs++;
                return const UpdateDone();
              },
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ProgressButton));
      await tester.pump();

      // The user leaves while the dialog is up.
      await tester.pumpWidget(const SizedBox.shrink());
      browsing.complete();
      await tester.pumpAndSettle();

      expect(
        installs,
        0,
        reason: 'nothing may be written once there is nothing to report it',
      );
    });
  });
}
