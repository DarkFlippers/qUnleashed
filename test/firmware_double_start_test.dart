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
    late _ParkedPicker picker;
    late Completer<void> browsing;

    setUp(() {
      (device, client) = mountedDevice();
      client.arriveQuietly();
      browsing = Completer<void>();
      picker = _ParkedPicker('C:/tmp/fw.tgz', browsing);
      FilePicker.platform = picker;
      addTearDown(() {
        if (!browsing.isCompleted) browsing.complete();
        // FirmwareUpdateTracker is a process-wide singleton, so a state left
        // by one case disables the button in the next - the guard under test
        // reads _inProgress, which is derived from it.
        FirmwareUpdateTracker.instance.clear(client.scopedDeviceId);
      });
    });

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
      await tester.pumpWidget(
        button(
          install: ({
            required source,
            required client,
            required onState,
          }) async => const UpdateDone(),
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
      // The handler guard alone stops the double install; this pins the
      // other half, so the button also *looks* refused rather than taking
      // a click that quietly does nothing.
      expect(
        tester.widget<ProgressButton>(target).onPressed,
        isNull,
        reason: 'and the button shows it is refused while the dialog is open',
      );

      // Not asserted beyond this: how many installs follow is downstream of
      // the picker count, and the picker count is the bug. One dialog means one
      // archive means one install.
    });
  });
}
