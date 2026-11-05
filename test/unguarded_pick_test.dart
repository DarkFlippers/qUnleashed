// What a user sees when the system picker refuses the pick. QUNLEASHED-K.
//
// `picker_guard_test.dart` holds the shape - that no picker call sits outside
// a `try`. This holds the half that was the actual complaint: the app
// disappeared. "Upload files" called `pickFiles` with no catch, from a
// `ListTile.onTap` that did not await the future either, so Android's
// `unknown_path` reached the zone, `PlatformDispatcher.onError` reported it
// fatal, and the browser was gone behind a dialog the user was still looking
// at.
//
// The test that matters is therefore the *absence* of an uncaught error, and
// `testWidgets` is what reports that: it fails a test whose zone takes one,
// which is exactly the pre-fix behaviour. Which means the zone check is doing
// the work in every case here, and only one of the three cases below carries an
// assertion that can fail on its own - so each case says which of the two is
// holding it:
//
//  * **the page survives** is the zone check, with a vacuity guard. The
//    assertion is there so the case cannot pass on a page that never built;
//  * **a sentence arrives** is the only independent one. Deleting the
//    notification fails this and nothing else;
//  * **the failure is on the record** is the other independent one, and the
//    one the commit's argument rests on: all four sites show the same
//    cause-free sentence, so the log line is the only thing that can tell two
//    reports apart. Without it, deleting every `LogService.caught` in the
//    change left the whole suite green - the budgets only fail upward. Three
//    of those four lines have moved into `components/folder_pick.dart` since
//    (#353), where `folder_pick_test.dart` asserts them; this case is what
//    holds the fourth, which is the file pick below.
//
// Mutations run, with the results: making the catch `rethrow` fails all three
// through the zone; deleting the notification fails only the second; deleting
// the `caught` call fails only the third.
//
// A fourth case was deliberately removed rather than kept. It tapped the FAB
// again and asserted the sheet reopened, claiming to watch for "a guard left
// armed" the way `oversized_pick_test.dart` does for the plotter. The plotter
// has `_picking` and a `finally`; this page has neither, the sheet is popped
// before the call, and the toast sits at the top of the overlay while the FAB
// is bottom-right. No mutation of this fix failed that case without also
// failing the first, which makes it the second detector wearing a third name -
// the "trusting that a test fails for the reason its name says" shape CLAUDE.md
// lists.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';

import 'archive_fakes.dart';
import 'firmware_fixture.dart';
import 'kept_lines.dart';

/// The failure the plugin actually reports, and the one that shipped the bug.
///
/// `unknown_path` is not a pick that came back with a null path - the page
/// handles that, and counts it as skipped. The Android delegate fails the
/// *whole* call when `FileUtils.openFileStream` answers null for what the
/// user chose, which is what a provider handing back no stream looks like
/// from here.
final _refused = PlatformException(
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
    // Set and not restored, as `oversized_pick_test.dart` does it, and not
    // laziness: `FilePicker.platform` is a `late` field with no value off a
    // real platform, so *reading* it to put it back is what throws. Safe
    // because every test that installs a picker does so before it pumps.
    FilePicker.platform = _RefusingPicker();
  });

  /// Opens the browser, then the FAB sheet, then taps Upload files.
  Future<void> tapUpload(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithDevice(FileManagerPage(client: storage), device),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.fmUploadFiles));
    await tester.pumpAndSettle();
  }

  testWidgets('a refused pick leaves the browser standing', (tester) async {
    await tapUpload(tester);

    // The listing is the page, and a page that is gone cannot show it. Framed
    // on what is still there rather than on "no exception", because the
    // uncaught error is what `testWidgets` reports by itself and an assertion
    // claiming to check it would pass on a page that never built at all.
    expect(find.text('notes.txt'), findsOneWidget);
  });

  testWidgets('and says the pick failed instead of nothing', (tester) async {
    await tapUpload(tester);

    expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
  });

  testWidgets('and keeps the cause, which the sentence does not carry', (
    tester,
  ) async {
    await tapUpload(tester);

    // `contains` on the body rather than equality: the line carries
    // `describe(e, st)`, so the stack is in it and would have to be pinned
    // here too. What is asserted is the part a reader of a report needs - the
    // area, the operation, and the plugin's own code, which is the whole of
    // what tells an unreadable file from a missing picker.
    expect(
      keptLines.where((line) => line.contains('[FileManager]')),
      hasLength(1),
      reason: 'the refusal has to leave exactly one line behind',
    );
    expect(keptLines.single, contains('unknown_path'));
    // Kept, not alerted. `caught` is the level ADR 0013 §5 gives an operation
    // that did not do what was asked and that nobody should be paged for; at
    // `warn` or `error` a broken provider would page somebody per tap.
    expect(keptLevels, [KeptLevel.caught]);
  });
}

/// Rejects every pick, the way the Android delegate does.
class _RefusingPicker extends FilePicker {
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
  }) async => throw _refused;
}
