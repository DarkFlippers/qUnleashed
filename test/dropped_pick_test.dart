// A multi-select upload that came back with none of the chosen files. #354.
//
// `_uploadFromPath` passes `allowMultiple: true`, and on that branch Android's
// delegate drops an item `FileUtils.openFileStream` cannot open and then calls
// `finishWithSuccess(files)` anyway (`FilePickerDelegate.java:119-136`). iOS
// does the same thing a different way: `UIDocumentPickerModeImport` moves each
// URL into the temp folder and skips the ones the move failed for. So a pick
// of five files where none could be read answers a non-null result carrying
// nothing, and `if (result == null || result.files.isEmpty) return;` read that
// as a cancellation - no toast, no log line, nothing, for a job that did not
// happen at all.
//
// **The cancel is the other half of this file**, and the reason it is here
// rather than left to the shape of the code: splitting the condition is only
// correct because a cancelled pick is null on both platforms that can drop an
// item - `finishWithSuccess(null)` for `RESULT_CANCELED` at
// `FilePickerDelegate.java:207`, `_result(nil)` from
// `documentPickerWasCancelled` on iOS. If that were wrong, this change would
// show an error toast on every cancelled pick, which is worse than the silence
// it replaces. The last case is what fails if the empty result is ever treated
// as the cancel's equal in the *other* direction - reporting on a null too.
//
// What is *not* here is a partial drop - four files uploaded of five chosen,
// reported as success. It cannot be: the chosen count never crosses the method
// channel, so nothing on this side can subtract. #354 keeps that half, and the
// comment in `_uploadFromPath` says so beside the code.
//
// Mutations run, with the results: folding `result.files.isEmpty` back into
// the null check fails the first two cases and leaves the third passing, which
// is the shape this file is for; deleting the notification fails the first;
// deleting the `LogService.caught` fails the second.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';

import 'archive_fakes.dart';
import 'firmware_fixture.dart';
import 'kept_lines.dart';
import 'picker_fakes.dart';

void main() {
  late DeviceController device;
  late ListingFlipper storage;

  setUp(() {
    recordKeptLines();
    (device, _) = mountedDevice();
    storage = ListingFlipper();
  });

  /// Opens the browser, then the FAB sheet, then taps Upload files.
  ///
  /// [picker] is installed before the pump and not restored, which
  /// `StubFilePicker` explains: `FilePicker.platform` is a `late` field with
  /// no value off a real platform, so reading it to put it back is what
  /// throws.
  Future<void> tapUpload(WidgetTester tester, FilePicker picker) async {
    FilePicker.platform = picker;
    await tester.pumpWidget(
      wrapWithDevice(FileManagerPage(client: storage), device),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.fmUploadFiles));
    await tester.pumpAndSettle();
  }

  testWidgets('a pick that returned none of the chosen files says so', (
    tester,
  ) async {
    await tapUpload(tester, StubFilePicker(result: FilePickerResult(const [])));

    // This also catches a `return` dropped from the branch, and not by luck:
    // `QNotification.show` closes the current card first, so an `_upload([])`
    // falling through would replace this toast with "Uploaded 0 files" and
    // leave nothing to find.
    expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
  });

  testWidgets('and leaves a line, which the sentence cannot carry', (
    tester,
  ) async {
    await tapUpload(tester, StubFilePicker(result: FilePickerResult(const [])));

    // The same sentence covers a refused pick and this one, so the line is
    // the only thing that tells a reader of a report which happened.
    expect(keptLines, hasLength(1));
    expect(keptLines.single, contains('[FileManager]'));
    expect(keptLines.single, contains('none of the chosen files'));
    // Kept, not alerted: a provider that will not open the user's own file is
    // nothing anybody can be paged for, while the rate of it is worth reading.
    expect(keptLevels, [KeptLevel.caught]);
  });

  testWidgets('a cancelled pick is still silent', (tester) async {
    // Null, the way both platforms report a cancelled pick.
    await tapUpload(tester, StubFilePicker());

    // Nothing on screen and nothing on the record. A null result is the
    // cancel on both platforms, and a toast per cancelled pick is the
    // regression this split has to avoid.
    expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
    expect(keptLines, isEmpty);
    // The page is still there, which is what makes the two findsNothing above
    // mean something rather than passing on a tree that never built.
    expect(find.text('notes.txt'), findsOneWidget);
  });
}
