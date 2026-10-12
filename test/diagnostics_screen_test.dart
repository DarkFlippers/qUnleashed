// The Diagnostics screen, which is now two switches.
//
// This file used to be `log_screen_test.dart` and tested the log list, the
// caution above it, Copy, Clear and refresh. ADR 0013 §1 removed all of that:
// Sentry is the only channel, so there is no in-app history to show, nothing
// to copy into an issue and nothing to clear. What is left is the switch that
// decides whether anything is reported at all, which is the whole screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/cardlist.dart';
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

/// The `Switch` belonging to the row headed [title].
///
/// `find.byType(Switch)` was enough while there was one row and is ambiguous
/// now - it matched both and every tap threw. Scoped through the row's own
/// `Row`, nearest first, so each case names the switch it means.
///
/// Anchored on `GroupedCard`, the widget `GroupedCardList` wraps each item in,
/// so it survives a `Row` being added inside a tile. `find.ancestor(..., Row)`
/// with `.first` worked too, but would then quietly pick the inner `Row` and
/// go on passing while scoping to the wrong thing.
Finder switchFor(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(GroupedCard)),
  matching: find.byType(Switch),
);

/// Where the switch headed [title] is sitting.
///
/// A sibling to [switchFor] because `tester.widget<Switch>(...).value` around
/// it does not fit a line, so every assertion about a switch position was a
/// four-line block.
bool switchValue(WidgetTester tester, String title) =>
    tester.widget<Switch>(switchFor(title)).value;

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
    expect(switchValue(tester, l10nGlobal.diagnosticsShareTitle), isTrue);
  });

  testWidgets('turning it off moves the switch and the stored value', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(switchFor(l10nGlobal.diagnosticsShareTitle));
    await tester.pumpAndSettle();

    expect(switchValue(tester, l10nGlobal.diagnosticsShareTitle), isFalse);
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

    expect(switchValue(tester, l10nGlobal.diagnosticsShareTitle), isFalse);
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

  group('the replay row', () {
    testWidgets('is on, and says what is blacked out of it', (tester) async {
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text(l10nGlobal.diagnosticsReplayTitle), findsOneWidget);
      // The masks are a promise the code keeps in `options.dart`, and this is
      // the only place the user is told about them.
      expect(find.text(l10nGlobal.diagnosticsReplaySubtitle), findsOneWidget);
      expect(switchValue(tester, l10nGlobal.diagnosticsReplayTitle), isTrue);
    });

    testWidgets('turning it off stores the choice and leaves sharing on', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(switchFor(l10nGlobal.diagnosticsReplayTitle));
      await tester.pumpAndSettle();

      expect(lastSettings!.shareReplay, isFalse);
      // The two are separate answers, and the subordinate one must not drag
      // the other with it.
      expect(lastSettings!.shareLogs, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('diagnostics.share_replay'), isFalse);
    });

    testWidgets('goes away when sharing is turned off', (tester) async {
      // Rather than sitting there disabled. With nothing being sent there is
      // nothing for a replay to attach to, and a switch that does nothing is
      // worse than no switch.
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text(l10nGlobal.diagnosticsReplayTitle), findsOneWidget);

      await lastSettings!.setShareLogs(false);
      await tester.pumpAndSettle();

      expect(find.text(l10nGlobal.diagnosticsReplayTitle), findsNothing);
    });

    testWidgets('comes back where the user left it', (tester) async {
      // The value survives the row being hidden, so turning sharing back on
      // does not quietly re-enable a replay somebody switched off.
      //
      // Set through the object rather than seeded into the preference store:
      // `getInstance` caches per isolate, so a `setMockInitialValues` in a
      // test body lands after the store this page already read and the case
      // passes on the default it was trying to override.
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();
      await lastSettings!.setShareReplay(false);
      await tester.pumpAndSettle();

      await lastSettings!.setShareLogs(false);
      await tester.pumpAndSettle();
      await lastSettings!.setShareLogs(true);
      await tester.pumpAndSettle();

      expect(switchValue(tester, l10nGlobal.diagnosticsReplayTitle), isFalse);
    });

    testWidgets('tapping its row is the same as tapping its switch', (
      tester,
    ) async {
      // The `onTap` is keyed by row now, so the two rows can and did route to
      // the same switch - this is what catches that.
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10nGlobal.diagnosticsReplayTitle));
      await tester.pumpAndSettle();

      expect(lastSettings!.shareReplay, isFalse);
      expect(lastSettings!.shareLogs, isTrue);
    });

    testWidgets('is not offered where replay cannot record', (tester) async {
      // Replay is native-backed and `ReplayIntegration` gates on
      // `supportsReplay`, so the four desktop targets record nothing
      // whatever the rate says. Offering the switch there promises a
      // recording that never happens, in the one screen where a false
      // statement costs the most - and tapping it used to tear the SDK down
      // and back up to apply a rate no recorder would read, paying a
      // synchronous `sentry_close()` to do it.
      //
      // A `variant` and not a `setUp`: `testWidgets` asserts every
      // foundation debug variable is unset by the end of the body, so an
      // override held across the test fails it. The variant brackets the
      // body properly. Every other case here needs no variant because a
      // widget test already runs as Android.
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text(l10nGlobal.diagnosticsShareTitle), findsOneWidget);
      expect(find.text(l10nGlobal.diagnosticsReplayTitle), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
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
