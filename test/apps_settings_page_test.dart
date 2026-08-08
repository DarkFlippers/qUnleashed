import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/pages/apps/data/apps_backend.dart';
import 'package:qunleashed/pages/apps/data/catalog_mode.dart';
import 'package:qunleashed/pages/option/pages/apps.dart';
import 'package:qunleashed/theme/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

void main() {
  testWidgets('apps settings show the mode choice and the status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The catalog is unreachable from a test, so the resolution has to run
    // outside the fake async zone to reach its manager-only verdict.
    await tester.runAsync(
      () => AppsBackend.instance.resolveMode(force: true),
    );

    await tester.pumpWidget(_wrap(const AppsSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('Catalog mode'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Catalog only'), findsOneWidget);
    expect(find.text('Build from source'), findsOneWidget);
    expect(find.text('Apps manager only'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Catalog APIs'), findsOneWidget);
    expect(find.text('Re-check'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);

    expect(AppsBackend.instance.mode.value, CatalogMode.managerOnly);
    expect(find.text('Manager only'), findsOneWidget);
    expect(find.text('No answer'), findsNWidgets(2));

    await tester.tap(find.text('Apps manager only'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(AppsBackend.instance.preference, CatalogModePreference.manager);

    await tester.runAsync(
      () => AppsBackend.instance.setPreference(CatalogModePreference.auto),
    );
    expect(tester.takeException(), isNull);
  });
}
