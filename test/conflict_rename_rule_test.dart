// The replace-or-skip dialog's rename field, which is the fifth name prompt
// and the easiest to miss.
//
// Its own rule was `empty / '.' / '..' / contains '/'`, so a tab, a `?`, a
// Cyrillic letter or a 300-byte name went straight through to an RPC write
// that answered with a failure naming no cause. It takes the shared rule now,
// and keeps its own collision check as the extra - in that order, because a
// name the device refuses is refused whatever else is on the card. #277
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/controller.dart';
import 'package:qunleashed/pages/archive/browser/widgets/replace_dialog.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

void main() {
  /// The dialog, already in rename mode for one conflicting file.
  Future<void> openRename(
    WidgetTester tester, {
    List<String> siblings = const [],
    String conflicting = 'gate.sub',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ReplaceFilesDialog.show(
              context,
              destination: '/ext',
              items: 1,
              conflicts: [
                FileConflict(
                  name: conflicting,
                  size: 10,
                  existingSize: 20,
                  siblings: siblings.toSet(),
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The dialog's own Rename button, which opens the field with a suggested
    // name selected.
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();
  }

  testWidgets('refuses a character the Flipper will not carry', (tester) async {
    await openRename(tester);

    await tester.enterText(find.byType(TextField), 'gate?one');
    await tester.pump();

    expect(find.textContaining(r'\ / : * ? " < > |'), findsOneWidget);
  });

  testWidgets('still refuses a name that is taken', (tester) async {
    await openRename(tester, siblings: const ['taken.sub']);

    await tester.enterText(find.byType(TextField), 'taken.sub');
    await tester.pump();

    expect(find.text('A file with this name already exists'), findsOneWidget);
  });

  testWidgets('reports the storage rule before the collision', (tester) async {
    // Both at once: the name is taken *and* carries a `?`. The device's
    // refusal is the one to act on, because the other name has to satisfy it
    // too.
    await openRename(tester, siblings: const ['taken?.sub']);

    await tester.enterText(find.byType(TextField), 'taken?.sub');
    await tester.pump();

    expect(find.text('A file with this name already exists'), findsNothing);
    expect(find.textContaining(r'\ / : * ? " < > |'), findsOneWidget);
  });

  // The disabled button is not the whole gate: the field's own submit calls
  // `_applyRename` directly, which is where the second check lives. No test
  // reached that function at all before this one.
  testWidgets('cannot be submitted from the keyboard either', (tester) async {
    await openRename(tester);

    await tester.enterText(find.byType(TextField), 'gate?one');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'still asking, not applied',
    );
  });

  // The suggestion the dialog prefills has to be one its own field accepts.
  // For `.gitkeep` the stem is the whole name, so `.gitkeep (2)` was offered
  // and then refused as a leading dot - a dialog arguing with itself.
  testWidgets('suggests a name it would accept for a dotted file', (
    tester,
  ) async {
    await openRename(tester, conflicting: '.gitkeep');

    expect(find.textContaining(r'\ / : * ? " < > |'), findsNothing);
    expect(find.text('A name cannot start or end with a dot.'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'gitkeep (2)',
    );
  });

  testWidgets('accepts a name the device will take', (tester) async {
    await openRename(tester);

    await tester.enterText(find.byType(TextField), 'gate-2.sub');
    await tester.pump();

    expect(find.textContaining(r'\ / : * ? " < > |'), findsNothing);
    expect(find.text('A file with this name already exists'), findsNothing);
  });
}
