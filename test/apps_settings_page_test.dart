import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/pages/apps/data/apps_backend.dart';
import 'package:qunleashed/pages/apps/data/catalog_mode.dart';
import 'package:qunleashed/pages/option/pages/apps.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

/// The page also starts its own catalog request, which times out after 15 s;
/// fake time is moved past it so no timer outlives the test.
Future<void> _drainCatalog(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 16));

Future<void> _open(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues(const {});
  // The page reads its width from MediaQuery to tell a phone from a desktop.
  sizeView(tester, size);
  // The catalog is unreachable from a test, so the resolution has to run
  // outside the fake async zone to reach its manager-only verdict.
  await tester.runAsync(() => AppsBackend.instance.resolveMode(force: true));
  await tester.pumpWidget(_wrap(const AppsSettingsPage()));
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('apps settings show the current values and change them in '
      'dialogs on a phone', (tester) async {
    await _open(tester, const Size(420, 1600));

    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('Catalog server'), findsOneWidget);
    expect(find.text('Catalog mode'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Catalog APIs'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Flibler'), findsOneWidget);
    // Re-checking is an action: an icon button at the end of the row it
    // refreshes, named by its tooltip.
    expect(find.byTooltip('Re-check'), findsOneWidget);

    // The rows show the picked value: the catalog mode and Flibler's build
    // backend are both automatic.
    expect(AppsBackend.instance.mode.value, CatalogMode.managerOnly);
    expect(find.text('Automatic'), findsNWidgets(2));
    expect(find.text('No answer'), findsOneWidget);

    // The options live in the dialog, the row only shows the current one.
    await tester.tap(find.text('Catalog mode'));
    await tester.pumpAndSettle();
    expect(_inDialog('Automatic'), findsOneWidget);
    expect(_inDialog('Catalog only'), findsOneWidget);
    expect(_inDialog('Build from source'), findsOneWidget);
    expect(_inDialog('Apps manager only'), findsOneWidget);

    // A plain choice applies on tap and closes the dialog.
    await tester.tap(_inDialog('Apps manager only'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(AppsBackend.instance.preference, CatalogModePreference.manager);
    expect(find.text('Apps manager only'), findsOneWidget);

    // The server dialog takes another domain in the field under the last
    // option and refuses one it cannot use.
    final server = AppsBackend.instance.api.server;
    await tester.tap(find.text('Catalog server'));
    await tester.pumpAndSettle();
    expect(_inDialog('Official catalog'), findsOneWidget);
    expect(_inDialog('Custom domain'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not a domain/path');
    await tester.tap(_inDialog('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a domain, optionally with http:// or https://'),
      findsOneWidget,
    );
    await tester.tap(_inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(AppsBackend.instance.api.server, server);

    await tester.runAsync(
      () => AppsBackend.instance.setPreference(CatalogModePreference.auto),
    );
    await _drainCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'on a desktop a choice is a group of option pieces with leading radios, '
    'and the column keeps its width',
    (tester) async {
      await _open(tester, const Size(1400, 2000));

      // The column is centred at 720 px instead of running edge to edge.
      final row = tester.getRect(find.text('Catalog mode'));
      expect(row.left, greaterThan((1400 - 720) / 2));
      expect(row.right, lessThan(1400 - (1400 - 720) / 2));

      // No dialog and no dropdown: each option is a piece of the setting's
      // own group, the radio leading and the text after it, with the status
      // under the group.
      expect(find.text('Catalog only'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Catalog only')).dx,
        greaterThan(tester.getTopLeft(find.text('Catalog mode')).dx),
      );
      await tester.tap(find.text('Catalog only'));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(AppsBackend.instance.preference, CatalogModePreference.catalog);

      // The custom server's field opens under its radio and refuses a
      // domain it cannot use; nothing changes until it is saved.
      final server = AppsBackend.instance.api.server;
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Custom domain'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(find.byType(TextField), 'not a domain/path');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a domain, optionally with http:// or https://'),
        findsOneWidget,
      );
      expect(AppsBackend.instance.api.server, server);

      await tester.runAsync(
        () => AppsBackend.instance.setPreference(CatalogModePreference.auto),
      );
      await _drainCatalog(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
