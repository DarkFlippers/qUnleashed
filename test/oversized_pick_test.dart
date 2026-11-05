// What a user sees when the pick is too big to import. QUNLEASHED-E.
//
// `picked_file_test.dart` holds `readPickedFile` itself. This holds the half
// that was the actual complaint: the app used to vanish, and the fix is only
// worth having if a sentence arrives in its place. That sentence comes from
// an `on PickedFileTooLarge` clause at each call site, and deleting either
// one leaves a green suite - the generic `catch` below it swallows the
// exception and shows "could not read" instead, which is the pre-fix message
// for a post-fix situation.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/plotter/page.dart';
import 'package:qunleashed/services/localization/l10n.dart';

import 'firmware_fixture.dart';

void main() {
  late Directory dir;
  late String bigPath;

  /// Comfortably over the plotter's 2 MB limit, and not a rounding away from
  /// it: at `limit + 1` both halves of the sentence render the same figure
  /// and the test cannot tell the size from the limit, nor notice the two
  /// swapped.
  const bigBytes = 8 * 1024 * 1024;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('oversized_pick_test');
    // Truncated to length rather than written: the filesystem reports the
    // size either way and the gate only stats it, so writing 8 MB per test
    // run to prove a refusal would be the cost the refusal exists to avoid.
    bigPath = '${dir.path}${Platform.pathSeparator}clip.mp4';
    final handle = File(bigPath).openSync(mode: FileMode.write);
    handle.truncateSync(bigBytes);
    handle.closeSync();
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  testWidgets('the plotter says how big the pick was, and what fits', (
    tester,
  ) async {
    FilePicker.platform = _OversizedPicker(bigPath);
    final (device, _) = mountedDevice();

    await tester.pumpWidget(wrapWithDevice(const PulsePlotterPage(), device));
    await tester.pumpAndSettle();

    await _tapOpen(tester);

    expect(
      find.text(l10nGlobal.commonFileTooLarge('8.0 MB', '2.0 MB')),
      findsOneWidget,
    );

    await closeDevice(tester, device);
  });

  testWidgets('the plotter is usable again after a refusal', (tester) async {
    // The refusal leaves through a `catch`, and the guard that stops a second
    // dialog is released in the `finally` below it. A refusal that latched
    // the button would be a worse bug than the one being fixed - the page
    // would need restarting to try a smaller file.
    final picker = _OversizedPicker(bigPath);
    FilePicker.platform = picker;
    final (device, _) = mountedDevice();

    await tester.pumpWidget(wrapWithDevice(const PulsePlotterPage(), device));
    await tester.pumpAndSettle();

    await _tapOpen(tester);
    await _tapOpen(tester);

    expect(picker.opened, 2);

    await closeDevice(tester, device);
  });
}

/// Taps the open button and lets the handler finish.
///
/// `runAsync` because the handler now does real file I/O: `readPickedFile`
/// stats and reads the path, and neither completes inside the fake-async zone
/// `testWidgets` runs in. Without it `_pickFile` never returns, its `finally`
/// never releases the re-entrancy guard, and the button stays disabled - a
/// test written without this reads as "the refusal latched the page" when
/// what latched was the test.
Future<void> _tapOpen(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byTooltip('Open signal file'));
    // A fixed span, because the thing being waited for is a `stat` and the
    // overlay it leads to cannot be polled for from in here - the tree does
    // not rebuild without a pump, and pumping inside `runAsync` is its own
    // hazard. 50 ms against a stat of a local file is generous.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

/// Hands back one real, oversized file.
class _OversizedPicker extends FilePicker {
  _OversizedPicker(this.path);

  final String path;

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
    // `size` is deliberately a lie, and a small one: the cap has to come from
    // the file, not from what the pick claims about it.
    return FilePickerResult([
      PlatformFile(name: 'clip.mp4', size: 1, path: path),
    ]);
  }
}
