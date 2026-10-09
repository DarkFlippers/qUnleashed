// ADR 0013 §1's one-time notice: what it says, what its two actions do, and
// above all that it is a notice rather than a gate.
//
// The three failures worth holding are all about "one time". Shown again at
// every launch is the one a user would report; never shown at all is the one
// that matters legally and that nobody would report; and shown but not
// recorded because the user swiped it away rather than tapping is the one that
// looks like the first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/option/diagnostics_notice.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/telemetry/settings.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unopenable_prefs.dart';

/// A screen that raises the notice from its first frame, the way `AppShell`
/// does.
///
/// A host of its own rather than pumping `AppShell`: that widget builds the
/// whole app - archive controller, push service, home-widget channels - and
/// none of it is what this is about. What is reproduced is the one thing that
/// matters, a post-frame callback with a context inside a Navigator.
class _NoticeHost extends StatefulWidget {
  const _NoticeHost(this.settings);

  final DiagnosticsSettings settings;

  @override
  State<_NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<_NoticeHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDiagnosticsNoticeIfDue(context, widget.settings);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Widget wrap(DiagnosticsSettings settings) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: _NoticeHost(settings),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Finder notice() => find.text(l10nGlobal.diagnosticsNoticeTitle);

  testWidgets('a fresh install is told what is sent and what never is', (
    tester,
  ) async {
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget);
    expect(find.text(l10nGlobal.diagnosticsNoticeBody), findsOneWidget);
    // The one claim a user of this app cannot check for themselves.
    expect(l10nGlobal.diagnosticsNoticeBody, contains('never sent'));
    // No consent is being asked for, so there is no refusing action - only an
    // acknowledgement and a way out.
    expect(find.text(l10nGlobal.commonGotIt), findsOneWidget);
    expect(find.text(l10nGlobal.diagnosticsNoticeTurnOff), findsOneWidget);
  });

  testWidgets('reporting is already on while the notice is on screen', (
    tester,
  ) async {
    // This is the difference between a notice and a gate, and it is the whole
    // of §1's reversal. If this ever inverts, the decision has changed and the
    // ADR has to change with it.
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget);
    expect(settings.shareLogs, isTrue);
  });

  testWidgets('Got it closes it and leaves sharing on', (tester) async {
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10nGlobal.commonGotIt));
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
    expect(settings.shareLogs, isTrue);
  });

  testWidgets('Turn it off closes it and turns sharing off', (tester) async {
    // One tap at the moment the user is being told, rather than a hunt through
    // Settings afterwards.
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10nGlobal.diagnosticsNoticeTurnOff));
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
    expect(settings.shareLogs, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('diagnostics.share_logs'), isFalse);
  });

  testWidgets('somebody who has seen it is not shown it again', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'diagnostics.notice_shown': true,
    });
    await tester.pumpWidget(wrap(DiagnosticsSettings()));
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
  });

  testWidgets('it is recorded as shown before it is answered', (tester) async {
    // A swipe-dismiss returns the same null as a lost route, so a notice
    // recorded only on a tap comes back at every launch for anyone who swipes
    // it away - which reads exactly like the bug where it is never recorded at
    // all.
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget, reason: 'still open, nothing tapped');
    expect(settings.noticeShown, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('diagnostics.notice_shown'), isTrue);
  });

  testWidgets('dismissing it counts as Got it', (tester) async {
    // §1: the app is usable behind it and dismissing is the same as **Got
    // it**. Driven by popping the route, which is what a tap outside and a
    // swipe both come down to.
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(notice())).pop();
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
    expect(settings.shareLogs, isTrue);
    expect(settings.noticeShown, isTrue);
  });

  testWidgets('a store that will not open shows it rather than skipping it', (
    tester,
  ) async {
    // The opposite direction from the sharing switch's default, on purpose:
    // being told twice is a nuisance, never being told is the failure that
    // matters.
    useUnopenablePrefs();
    final settings = DiagnosticsSettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget);
    expect(settings.loaded, isFalse, reason: 'the read really did fail');
    // And the write of the shown flag fails the same way, so it is offered
    // again next launch rather than silently suppressed by a half-write.
    expect(settings.noticeShown, isTrue, reason: 'in memory, for this run');
  });
}
