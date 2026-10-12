// The file manager's inline rename, which is the one name prompt that is not
// a dialog.
//
// It is a text field in the row, so there is nowhere to put an error message
// and nothing to disable - which is why it validated only "empty" and
// "unchanged" and sent everything else to `rename`. A `/` in the name came
// back as "Could not rename" with no cause named, which is the failure #277
// exists to remove. It refuses in a toast instead, and keeps the editor open
// on the name the user typed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/columns.dart';
import 'package:qunleashed/pages/archive/browser/controller.dart';
import 'package:qunleashed/pages/archive/browser/widgets/file_row.dart';
import 'package:qunleashed/pages/archive/browser/widgets/file_table.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

void main() {
  final entry = RemoteEntry(name: 'gate.sub', size: 10, isDir: false);

  /// The row, in edit mode, with whatever rename handler the test wants.
  Future<void> pumpRow(
    WidgetTester tester, {
    required Future<void> Function(String) onRename,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
        home: Scaffold(
          body: FileTableRow(
            entry: entry,
            // The name column alone, which is the one the editor replaces.
            cols: const [
              (col: FileCol('Name', 0, sortKey: 'name'), width: 400),
            ],
            actions: FileEntryActions(onRename: onRename),
            onTap: () {},
            // Opens the editor without going through the actions sheet, which
            // is what the page passes after a rename is asked for.
            autoEdit: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('refuses a name the Flipper will not carry', (tester) async {
    final asked = <String>[];
    await pumpRow(tester, onRename: (name) async => asked.add(name));

    await tester.enterText(find.byType(TextField), 'gate/one');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(asked, isEmpty, reason: 'the rename never reaches the device');
    expect(find.textContaining(r'\ / : * ? " < > |'), findsOneWidget);
    // Still editing, because the only place the user can fix it is the field
    // they typed into.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('refuses a name outside ASCII', (tester) async {
    final asked = <String>[];
    await pumpRow(tester, onRename: (name) async => asked.add(name));

    await tester.enterText(find.byType(TextField), 'Ворота');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
  });

  testWidgets('renames when the name is one the device will take', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpRow(tester, onRename: (name) async => asked.add(name));

    await tester.enterText(find.byType(TextField), 'gate-2.sub');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(asked, ['gate-2.sub']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('closes without complaining when the field is cleared', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpRow(tester, onRename: (name) async => asked.add(name));

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(find.byType(TextField), findsNothing);
    // No toast: an error about a field the user has just cleared reads as a
    // complaint about their typing, which is the same call QNameDialog makes.
    expect(find.text('Type a name.'), findsNothing);
  });

  // The way out of an editor a refused name keeps open. Clearing the field
  // also closes it, which is not something anyone would guess.
  testWidgets('can be abandoned without renaming', (tester) async {
    final asked = <String>[];
    await pumpRow(tester, onRename: (name) async => asked.add(name));

    await tester.enterText(find.byType(TextField), 'gate/one');
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('says nothing about a name left unchanged', (tester) async {
    final asked = <String>[];
    await pumpRow(tester, onRename: (name) async => asked.add(name));

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });
}
