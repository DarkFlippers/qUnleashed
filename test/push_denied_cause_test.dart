// That Settings → Push names the cause it actually knows.
//
// The defect, from #351: `PushService.isUnavailable` is set for *any* throw
// out of `start` — a missing Play Services, a network blip during Firebase
// init, a denied notification permission — and this page rendered
// "This build is not signed for push" for all of them. A confident statement
// of the wrong cause is worse than silence, because the reader stops looking.
//
// The first version of this file could not test that. `isUnavailable` is a
// private static written only inside `start()`'s Firebase catch, which a test
// cannot reach, and `topicsSupported` reads `defaultTargetPlatform` — which
// under `flutter test` is `android`, so `supported` was true and the whole
// `if (!supported)` branch was unreachable. `findsNothing` for a sentence that
// could never render passed either way: reverting the fix left it green. It is
// the shape CLAUDE.md warns about, and it was guarding the one assertion that
// mattered.
//
// `debugSetUnavailable` exists for that. With it the branch is reachable, and
// the two assertions below are both falsifiable: the denial is named, *and*
// the build sentence is gone while it is.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/option/pages/push.dart';
import 'package:qunleashed/services/notifications/push_service.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/permissions/permission.dart';
import 'package:qunleashed/services/permissions/scope.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'view_size.dart';

/// The page under a scope, as `MaterialApp.builder` provides one.
Widget _wrap(PermissionCenter center) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: PermissionScope(
    notifier: center,
    child: const NotificationsSettingsPage(),
  ),
);

/// A centre with the push permission refused.
PermissionCenter _denied() =>
    PermissionCenter()
      ..record(AppPermission.pushNotifications, PermissionOutcome.denied);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    // The state this page's wrong-cause branch keys off. A static with no
    // owner, so it is set and cleared per test.
    PushService.debugSetUnavailable(true);
  });

  tearDown(() => PushService.debugSetUnavailable(false));

  Future<void> pumpPage(WidgetTester tester, PermissionCenter center) async {
    sizeView(tester, const Size(900, 1600));
    await tester.pumpWidget(_wrap(center));
    await tester.pumpAndSettle();
  }

  testWidgets('with no denial on record the build sentence is shown', (
    tester,
  ) async {
    // The control, and what makes the next two mean anything: the sentence is
    // reachable, so a test asserting its absence is actually asserting
    // something. Push really is unavailable here and no permission has been
    // refused, so the build sentence is the honest answer.
    await pumpPage(tester, PermissionCenter());

    expect(find.textContaining('not signed for push'), findsOneWidget);
    expect(find.text('Notifications are turned off'), findsNothing);
  });

  testWidgets('a denied permission is named, and the build claim is not', (
    tester,
  ) async {
    await pumpPage(tester, _denied());

    expect(
      find.text('Notifications are turned off'),
      findsOneWidget,
      reason: 'the cause the app actually knows',
    );
    expect(
      find.textContaining('not signed for push'),
      findsNothing,
      reason: 'the page must not also assert a cause it has not established',
    );
  });

  testWidgets('dismissing the notice does not bring the wrong cause back', (
    tester,
  ) async {
    // The regression this file exists for. The build sentence is suppressed by
    // the *denial*, not by the notice being on screen — so one tap of Dismiss
    // must not restore a claim that is still false. Keyed off `shouldNotice`
    // rather than `outcomeOf` it did exactly that.
    final center = _denied();
    await center.dismiss(AppPermission.pushNotifications);
    await pumpPage(tester, center);

    expect(
      find.text('Notifications are turned off'),
      findsNothing,
      reason: 'the user asked it to stop nagging, and it has',
    );
    expect(
      find.textContaining('not signed for push'),
      findsNothing,
      reason: 'still not a claim this build has established',
    );
  });

  testWidgets('a granted permission leaves the build sentence alone', (
    tester,
  ) async {
    // Granting the permission does not make the build signed. Only the denial
    // suppresses that sentence, and nothing else should.
    final center = PermissionCenter()
      ..record(AppPermission.pushNotifications, PermissionOutcome.granted);
    await pumpPage(tester, center);

    expect(find.textContaining('not signed for push'), findsOneWidget);
    expect(find.text('Notifications are turned off'), findsNothing);
  });

  group('every authorization status maps to one outcome', () {
    // The arms of `outcomeOf` are a product decision - two statuses mean
    // usable, two mean refused, one means nothing has been answered - and
    // until this group existed nothing executable said so. `flutter analyze`
    // only requires the switch to be *exhaustive*, so changing any single arm
    // to a different `PermissionOutcome` passed the analyzer, all 2523 tests
    // and the format gate together. That is how `deniedPermanently` could
    // have been pointed at `granted` by a slip and shipped.
    //
    // So the table is deliberately complete rather than one case for the
    // status that prompted it. A `switch` over the enum here would defeat
    // the point: it would track whatever the function does.
    const expected = <AuthorizationStatus, PermissionOutcome>{
      AuthorizationStatus.authorized: PermissionOutcome.granted,
      // iOS delivering quietly without having asked. Not a refusal.
      AuthorizationStatus.provisional: PermissionOutcome.granted,
      AuthorizationStatus.denied: PermissionOutcome.denied,
      // Android 13+ refusing to prompt again. Folds into `denied` because
      // the route out of both is the same settings page.
      AuthorizationStatus.deniedPermanently: PermissionOutcome.denied,
      // Never answered - and `unknown` draws no notice, which is the whole
      // of #351: a notice raised on a guess states the wrong cause.
      AuthorizationStatus.notDetermined: PermissionOutcome.unknown,
    };

    test('the table covers the enum', () {
      // Fails when `firebase_messaging` adds a status, which is the event
      // this file wants to hear about: the plugin added `deniedPermanently`
      // in 16.7.1 and the only thing that noticed was the analyzer.
      expect(
        expected.keys.toSet(),
        AuthorizationStatus.values.toSet(),
        reason: 'a new AuthorizationStatus needs a decision, not a default',
      );
    });

    for (final entry in expected.entries) {
      test('${entry.key.name} is ${entry.value.name}', () {
        expect(PushService.outcomeOf(entry.key), entry.value);
      });
    }

    test('only a denial is put in front of the user', () {
      // `warrantsNotice` is the single predicate every surface asks, so the
      // mapping only matters inasmuch as it feeds that answer.
      final notices = {
        for (final s in AuthorizationStatus.values)
          s.name: PushService.outcomeOf(s).warrantsNotice,
      };
      expect(notices, {
        'authorized': false,
        'provisional': false,
        'denied': true,
        'notDetermined': false,
        'deniedPermanently': true,
      });
    });
  });
}
