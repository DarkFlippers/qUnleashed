// The Diagnostics screen, which is now one switch.
//
// This file used to be `log_screen_test.dart` and tested the log list, the
// caution above it, Copy, Clear and refresh. ADR 0013 §1 removed all of that:
// Sentry is the only channel, so there is no in-app history to show, nothing
// to copy into an issue and nothing to clear. What is left is the switch that
// decides whether anything is reported at all, which is the whole screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/option/diagnostics_scope.dart';
import 'package:qunleashed/pages/option/pages/diagnostics.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The switch the screen draws, fresh per test.
///
/// Returned through a variable rather than passed back, because the two tests
/// that drive the switch want to read it after a tap.
DiagnosticsSettings? lastSettings;

Widget wrap(Widget child, {DiagnosticsSettings? settings}) {
  lastSettings = settings ?? DiagnosticsSettings();
  return MaterialApp(
    theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
    // The real app mounts this in `MaterialApp.builder` so a pushed route is
    // inside it; here the page *is* the home, so wrapping it is the same scope
    // with less ceremony.
    home: DiagnosticsScope(notifier: lastSettings!, child: child),
  );
}

void main() {
  setUp(() {
    // The switch reads preferences on its first build. Without a mock store
    // every test would log a load failure, and the one asserting the default
    // would be passing on the fallback rather than on the read.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('is on, and says what is never sent', (tester) async {
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text(l10nGlobal.diagnosticsShareTitle), findsOneWidget);
    // The claim a user of this app cannot check for themselves, which is why
    // it is on the screen and not only in the ADR.
    expect(find.text(l10nGlobal.diagnosticsShareSubtitle), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('turning it off moves the switch and the stored value', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(lastSettings!.shareLogs, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('diagnostics.share_logs'), isFalse);
  });

  testWidgets('a value changed from elsewhere redraws the row', (tester) async {
    // The one-time notice's **Turn it off** is dismissed over whatever screen
    // is showing, so the row has to follow the object rather than hold its own
    // copy. A page keeping the value in its own state passes every test above
    // and fails only this one.
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pumpAndSettle();

    await lastSettings!.setShareLogs(false);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('tapping the row is the same as tapping the switch', (
    tester,
  ) async {
    // Both slots go through one `_toggle`, so this is really asserting that
    // the row's `onTap` is wired at all - it is easy to leave a
    // `GroupedCardList` without one and never notice, because the switch still
    // works.
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10nGlobal.diagnosticsShareTitle));
    await tester.pumpAndSettle();

    expect(lastSettings!.shareLogs, isFalse);
  });

  testWidgets('nothing offers to copy or clear a log any more', (tester) async {
    // The screen's whole former purpose. Asserted rather than assumed, because
    // leaving one of these behind would be a button that reads from a buffer
    // that no longer exists.
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_all_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}
