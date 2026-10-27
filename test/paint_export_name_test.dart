// The export name survives a pick that did not happen. #353.
//
// Pixel Draw's three export entry points resolve a name *before* the folder
// pick - `_resolveExportName` at `editor/page.dart`, then `_pickDestination` -
// so an unsaved project prompts, the pick is cancelled or refused, and until
// this the name the user had just typed was gone with no way to resume it.
// #353 called that the worst of the four surfaces, because the other three
// lose nothing but a tap.
//
// This mounts the editor, which the suite did not do before: two other files
// state "no test mounts that page" as the reason a gap is cheap
// (`picker_guard_test.dart`'s fourth condition, and the mutation note in
// `folder_pick_test.dart`). It costs 40 lines and one surface size - the
// editor toolbar overflows the default 800x600 - so the premise was worth
// retiring rather than repeating.
//
// The pick is answered at the plugin's channel and not through a
// `FilePicker.platform` fake, because `defaultTargetPlatform` is Android under
// `flutter_test` and that is the branch `pickFolder` takes there: a fake on
// `FilePicker.platform` would never be reached, and an *unregistered* channel
// does not answer at all, so the pick would simply hang.
//
// Mutations run: dropping `_lastExportName = name` fails the second case and
// nothing else, and offering `_suggestedName()` in its place fails the same
// one. The first case fails under neither, which is what makes it the control
// rather than a second detector.
//
// It also holds the dialog fix this file found, from the other side: before
// `_NamePrompt` owned the field's controller, the second case failed on "A
// TextEditingController was used after being disposed" the moment it dismissed
// the prompt. **Deleting `_NamePromptState.dispose` survives**, and that is
// honest rather than a gap: a controller never disposed is a leak with no
// observable behaviour, and the mutation that matters - disposing it at the
// `showDialog` call site - is the one this case caught.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/tools/paint/editor/page.dart';
import 'package:qunleashed/services/localization/l10n.dart';

import 'firmware_fixture.dart';
import 'picker_fakes.dart';
import 'view_size.dart';

void main() {
  late DeviceController device;

  setUp(() {
    (device, _) = mountedDevice();
    // The cancel: null, the way both mobile platforms report a dismissed
    // picker. A refusal is the same story for this page - `pickFolder`
    // reports it and answers null either way - and `folder_pick_test.dart`
    // is where the difference between the two is held.
    answerFolderPick();
  });

  /// Mounts the editor on a surface tall enough for its toolbars.
  Future<void> openEditor(WidgetTester tester) async {
    sizeView(tester, const Size(1400, 2400));
    await tester.pumpWidget(wrapWithDevice(const PaintPage(), device));
    await tester.pumpAndSettle();
  }

  /// Walks the overflow menu to Export, then to the PNG entry, which is the
  /// one offered for a single frame.
  Future<void> exportPng(WidgetTester tester) async {
    // By the icon and not by type: the frames strip carries a second
    // `PopupMenuButton<int>` (flip, rotate) with an explicit `more_horiz`,
    // while the app bar's keeps the default adaptive one.
    await tester.tap(find.byIcon(Icons.adaptive.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.paintExport));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.paintExportPngTitle));
    await tester.pumpAndSettle();
  }

  /// The text the name prompt is showing, which is what this file is about.
  String promptText(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
    );
    return field.controller?.text ?? '';
  }

  testWidgets('the first export prompt suggests a name', (tester) async {
    await openEditor(tester);

    await exportPng(tester);

    // The control: `_suggestedName()` for a single frame. Without it the
    // second case could pass on a prompt that was always pre-filled.
    expect(promptText(tester), 'drawing');
  });

  testWidgets('and a pick that did not happen does not discard it', (
    tester,
  ) async {
    await openEditor(tester);
    await exportPng(tester);

    await tester.enterText(find.byType(TextField), 'otter_walk');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10nGlobal.commonSave),
      ),
    );
    await tester.pumpAndSettle();
    // The pick answered null here, and all three export paths read that as
    // "cancelled" and return silently - which is right, and used to cost the
    // name as well.
    expect(find.byType(AlertDialog), findsNothing);

    await exportPng(tester);

    expect(promptText(tester), 'otter_walk');
  });
}
