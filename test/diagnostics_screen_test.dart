import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/option/diagnostics_scope.dart';
import 'package:qunleashed/pages/option/pages/diagnostics.dart';
import 'package:qunleashed/services/build_identity.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quiet_log.dart';

/// The switch the screen draws, fresh per test.
///
/// Returned rather than held in a variable the tests close over, because the
/// two that drive the switch want to read it back after a tap.
DiagnosticsSettings? lastSettings;

Widget wrap(Widget child, {DiagnosticsSettings? settings}) {
  lastSettings = settings ?? DiagnosticsSettings();
  return MaterialApp(
    theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
    // The real app mounts this in `MaterialApp.builder` so a pushed route is
    // inside it; here the page *is* the home, so wrapping it is the same
    // scope with less ceremony.
    home: DiagnosticsScope(notifier: lastSettings!, child: child),
  );
}

/// Answers `PackageInfo.fromPlatform()`, which copying now needs.
///
/// Without this the platform channel is unmocked and the copy never lands: the
/// build identity that goes at the head of the text is resolved behind an
/// await, and the test settles before a reply that is not coming. Mocking it
/// also means the header carries a real version rather than `unknown`, so the
/// assertion below can be about the format rather than about the absence of
/// one.
const _packageInfoChannel = MethodChannel(
  'dev.fluttercommunity.plus/package_info',
);

void mockPackageInfo(WidgetTester tester) {
  // The read is cached across tests, so the second one to ask would otherwise
  // be served whatever the first one's mocks produced.
  BuildIdentity.debugForget();
  addTearDown(BuildIdentity.debugForget);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _packageInfoChannel,
    (call) async => call.method == 'getAll'
        ? <String, String>{
            'appName': 'qUnleashed',
            'packageName': 'com.example.qunleashed',
            'version': '0.14.1',
            'buildNumber': '14001',
          }
        : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _packageInfoChannel,
      null,
    ),
  );
}

void main() {
  setUp(() {
    LogService.clearHistory();
    // The switch reads preferences on its first build. Without a mock store
    // every test would log a load failure, and the one asserting the default
    // would be passing on the fallback rather than on the read.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(LogService.clearHistory);

  group('the sharing switch', () {
    testWidgets('is on, and says what is never sent', (tester) async {
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text(l10nGlobal.diagnosticsShareTitle), findsOneWidget);
      // The claim the user cannot verify for themselves, so it is on the
      // screen rather than only in the ADR.
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

    testWidgets('a value changed from elsewhere redraws the row', (
      tester,
    ) async {
      // The one-time notice's **Turn it off** is dismissed over whatever
      // screen is showing, so the row has to follow the object rather than
      // hold its own copy. A page keeping the value in its own state passes
      // every test above and fails only this one.
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();

      await lastSettings!.setShareLogs(false);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('the log stays reachable with sharing off', (tester) async {
      // Turning the switch off is not meant to cost the local route from "it
      // failed" to a bug report. It is the rest of this screen.
      quietly(() => LogService.error('[CLI] write failed: no transport'));
      await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('write failed', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.copy_all_outlined),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  // The half that makes the other half worth anything. Errors survive a
  // release build now, but a buffer nobody can open is the same as no buffer.
  testWidgets('the screen shows what was recorded', (tester) async {
    quietly(() => LogService.error('[CLI] write failed: no transport'));

    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();

    expect(
      find.textContaining('write failed: no transport', findRichText: true),
      findsOneWidget,
    );
  });

  // An empty log means nothing went wrong, not that recording is off. Saying
  // nothing at all would leave the user unable to tell those apart.
  testWidgets('an empty log says so rather than showing a blank page', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();

    expect(find.text(l10nGlobal.logEmpty), findsOneWidget);
  });

  // Copying is the one thing anyone comes here to do: the app has no crash
  // reporting, so this is the whole route from "it failed" to a bug report.
  testWidgets('copying puts every entry on the clipboard', (tester) async {
    mockPackageInfo(tester);
    quietly(() {
      LogService.error('first failure');
      LogService.error('second failure');
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.copy_all_outlined));
    // Settled rather than pumped once: copying awaits the build identity it
    // puts at the head of the text, so the clipboard write is a microtask
    // behind the tap.
    await tester.pumpAndSettle();

    expect(copied, contains('first failure'));
    expect(copied, contains('second failure'));
    expect(
      copied,
      contains('\n\n'),
      reason:
          'a blank line between entries, so a stack trace does not run '
          'into the next timestamp',
    );
    // ADR 0014 §3: a log pasted into an issue has to say which build produced
    // it. Asserted against the mocked version rather than on the brand word
    // alone - `startsWith('qUnleashed ')` passed on `qUnleashed unknown`, so
    // the header losing its identity entirely, which is the regression §3 is
    // about, stayed green.
    //
    // `-local` because no `--dart-define` reaches a widget test, which is the
    // channel default and is asserted in build_identity_test.
    expect(
      copied,
      startsWith('qUnleashed 0.14.1-local · 14001'),
      reason: 'the build identity opens the paste, before any entry',
    );
  });

  // Every hand-rolled copy in the app discarded the future, so a refused
  // clipboard was an unhandled async error and the only signal was the
  // absence of a toast. On Android a payload past about a megabyte throws
  // rather than truncating, and 500 stack traces sit right at that line.
  testWidgets('a refused clipboard says so instead of going quiet', (
    tester,
  ) async {
    mockPackageInfo(tester);
    quietly(() => LogService.error('something to copy'));
    var attempted = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          attempted = true;
          throw PlatformException(code: 'TransactionTooLargeException');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.copy_all_outlined));
    // Three pumps, and not pumpAndSettle: one more than before, for the
    // build-identity await the copy now goes behind, and bounded rather than
    // settled because the toast being looked for dismisses itself - settling
    // runs past its whole lifetime and finds nothing.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(attempted, isTrue, reason: 'the clipboard write was never tried');
    expect(find.textContaining('TransactionTooLargeException'), findsOneWidget);
  });

  testWidgets('clearing empties the log and the screen with it', (
    tester,
  ) async {
    quietly(() => LogService.error('something to forget'));

    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.commonClear).last);
    await tester.pumpAndSettle();

    expect(LogService.history, isEmpty);
    expect(find.text(l10nGlobal.logEmpty), findsOneWidget);
  });

  // Clear sits beside Copy and destroys the only record there is.
  testWidgets('backing out of the confirmation keeps the log', (tester) async {
    quietly(() => LogService.error('worth keeping'));

    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.commonCancel).last);
    await tester.pumpAndSettle();

    expect(LogService.history, hasLength(1));
  });

  // The log is meant to be pasted into a public issue. Paths have the account
  // name taken out at the sink, but a message naming a card, a folder or a
  // Flipper cannot be cleaned up mechanically - so the user is told, above the
  // log itself and before the button that hands it over.
  testWidgets('the screen says what the log can contain', (tester) async {
    quietly(() => LogService.error('could not clear ~/Documents/x.ir'));

    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();

    expect(find.text(l10nGlobal.logPrivacyCaution), findsOneWidget);
  });

  // A snapshot on purpose - lines must not move under someone reading a
  // failure - so there has to be a way to ask for the newer ones.
  testWidgets('refreshing picks up what arrived since the page opened', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();

    quietly(() => LogService.error('arrived while the page was open'));
    expect(
      find.textContaining('arrived while', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(
      find.textContaining('arrived while', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('copy and clear are offered only when there is something to', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DiagnosticsSettingsPage()));
    await tester.pump();

    for (final icon in [Icons.copy_all_outlined, Icons.delete_outline]) {
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
            .onPressed,
        isNull,
        reason: '$icon does nothing on an empty log',
      );
    }
  });
}
