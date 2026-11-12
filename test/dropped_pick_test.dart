// A multi-select upload that came back with none of the chosen files. #354.
//
// What this file defends is the pair of outcomes: a pick that dropped
// everything says so, a cancelled one stays silent. Both are reachable and
// they differ, which is why the three cases are here.
//
// **The mechanism underneath them changed, and upstream is why.** It used to
// be that Android's delegate dropped an item it could not open and reported
// success anyway, so a pick of five unreadable files answered a result
// carrying nothing - and the code read that as a cancellation, leaving no
// toast, no log line and nothing at all for a job that did not happen.
// `android_file_picker` 2.1.1 made that case fail with `unknown_path` instead;
// see `_allDropped` below and the comment in `_uploadFromPath`. So the dropped
// pick is a rejection the call site's `catch` reports, and an empty list means
// a cancellation and nothing else.
//
// What is *not* here is a partial drop - four files uploaded of five chosen,
// reported as success. It cannot be: the chosen count never crosses the method
// channel, so nothing on this side can subtract. #354 keeps that half, and the
// comment in `_uploadFromPath` says so beside the code.
//
// Mutations run, with the results: deleting the `catch` in `_uploadFromPath`
// fails the first two cases (the rejection reaches the zone instead);
// returning from the empty branch without the `catch` reporting fails the
// first; deleting the `LogService.caught` fails the second.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';

import 'archive_fakes.dart';
import 'firmware_fixture.dart';
import 'kept_lines.dart';
import 'picker_fakes.dart';

/// What Android answers for a pick whose every chosen file was unreadable.
///
/// `FileUtils.kt`'s `handleFileResult`: `finishWithError("unknown_path",
/// "Failed to retrieve path.")` for an empty list.
final _allDropped = PlatformException(
  code: 'unknown_path',
  message: 'Failed to retrieve path.',
);

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
  Future<void> tapUpload(WidgetTester tester, FilePickerPlatform picker) async {
    FilePickerPlatform.instance = picker;
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
    await tapUpload(tester, StubFilePicker(failure: _allDropped));

    // This also catches a `return` dropped from the branch, and not by luck:
    // `QNotification.show` closes the current card first, so an `_upload([])`
    // falling through would replace this toast with "Uploaded 0 files" and
    // leave nothing to find.
    expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
  });

  testWidgets('and leaves a line, which the sentence cannot carry', (
    tester,
  ) async {
    await tapUpload(tester, StubFilePicker(failure: _allDropped));

    // The same sentence covers a refused pick and this one, so the line is
    // the only thing that tells a reader of a report which happened.
    expect(keptLines, hasLength(1));
    expect(keptLines.single, contains('[FileManager]'));
    expect(keptLines.single, contains('unknown_path'));
    // Kept, not alerted: a provider that will not open the user's own file is
    // nothing anybody can be paged for, while the rate of it is worth reading.
    expect(keptLevels, [KeptLevel.caught]);
  });

  testWidgets('a cancelled pick is still silent', (tester) async {
    // Empty, which is how every implementation reports a cancelled pick
    // since 12.0.0 mapped the channel's null to `[]`.
    await tapUpload(tester, StubFilePicker());

    // Nothing on screen and nothing on the record. A toast per cancelled pick
    // is the regression the branch above has to avoid.
    expect(find.text(l10nGlobal.commonPickFailed), findsNothing);
    expect(keptLines, isEmpty);
    // The page is still there, which is what makes the two findsNothing above
    // mean something rather than passing on a tree that never built.
    expect(find.text('notes.txt'), findsOneWidget);
  });
}
