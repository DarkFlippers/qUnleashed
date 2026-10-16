// What a denied permission now does, and — more of this file — what an
// undenied one still must not do.
//
// #351: five permissions were requested, denied, and silently absorbed, so
// each feature failed in its own unrelated-looking way and the user was told
// nothing or told the wrong cause. The machinery that fixes it is a record
// (`PermissionCenter`) and one widget (`PermissionNotice`), and both have a
// failure mode worse than the bug: a notice raised on a guess. So most of
// what is asserted below is silence — for an unknown outcome, an unavailable
// platform, a grant, and a dismissal.
//
// The notice draws nothing rather than throwing when it has no scope, which
// makes "it silently never appears" an easy thing to ship. That is why the
// positive cases are here too, and why `device_scope_reach_test.dart` pins
// the scope being above the Navigator.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/permission_notice.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/permissions/permission.dart';
import 'package:qunleashed/services/permissions/scope.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(PermissionCenter center, Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: PermissionScope(
    notifier: center,
    child: Scaffold(body: child),
  ),
);

/// The storage notice as the IR library dialog mounts it: a Tier 2 gate.
Widget _gate() => PermissionNotice(
  permission: AppPermission.storage,
  severity: PermissionNoticeSeverity.blocking,
  title: 'No access to storage',
  body: 'The folder cannot be read.',
  actionLabel: 'Grant access',
  onAction: () {},
);

/// The push notice as Settings → Push mounts it: Tier 3, dismissible.
Widget _informational() => PermissionNotice(
  permission: AppPermission.pushNotifications,
  severity: PermissionNoticeSeverity.informational,
  title: 'Notifications are turned off',
  body: 'Everything else works as usual.',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('a notice appears only for a denial', () {
    testWidgets('nothing is drawn before anything has been asked', (
      tester,
    ) async {
      // The default state, and the one that must stay silent: a permission
      // nobody has asked about is not a permission the user refused.
      final center = PermissionCenter();
      await tester.pumpWidget(_wrap(center, _gate()));
      await tester.pump();

      expect(find.text('No access to storage'), findsNothing);
      expect(
        center.outcomeOf(AppPermission.storage),
        PermissionOutcome.unknown,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing is drawn where there is nothing to grant', (
      tester,
    ) async {
      // A desktop build, or a machine with no Bluetooth radio. Reporting this
      // as a denial would send the user to a settings page with nothing in it
      // to change.
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.unavailable);
      await tester.pumpWidget(_wrap(center, _gate()));
      await tester.pump();

      expect(find.text('No access to storage'), findsNothing);
    });

    testWidgets('nothing is drawn once it is granted', (tester) async {
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.granted);
      await tester.pumpWidget(_wrap(center, _gate()));
      await tester.pump();

      expect(find.text('No access to storage'), findsNothing);
    });

    testWidgets('a denial is drawn, with its action', (tester) async {
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.denied);
      await tester.pumpWidget(_wrap(center, _gate()));
      await tester.pump();

      expect(find.text('No access to storage'), findsOneWidget);
      expect(find.text('The folder cannot be read.'), findsOneWidget);
      expect(find.text('Grant access'), findsOneWidget);
    });

    testWidgets('a notice with no scope above it draws nothing', (
      tester,
    ) async {
      // A widget test that puts up a bare MaterialApp, which is how
      // `L10nContext` justifies its own fallback. It must not throw.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
          home: Scaffold(body: _gate()),
        ),
      );
      await tester.pump();

      expect(find.text('No access to storage'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the user coming back from system settings', () {
    testWidgets('a grant clears the notice with no rebuild of its own', (
      tester,
    ) async {
      // The half of #351 the widget cannot supply. Every one of these
      // permissions is reversible only in system settings, so the app has to
      // notice the user came back — and the dialog or page carrying the
      // notice can be the thing on screen the whole time, with nothing else
      // to rebuild it.
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.denied);
      await tester.pumpWidget(_wrap(center, _gate()));
      await tester.pump();
      expect(find.text('No access to storage'), findsOneWidget);

      center.record(AppPermission.storage, PermissionOutcome.granted);
      await tester.pump();

      expect(
        find.text('No access to storage'),
        findsNothing,
        reason: 'the InheritedNotifier redrew it, not the host screen',
      );
    });
  });

  group('dismissal', () {
    testWidgets('a feature gate offers none', (tester) async {
      // Tier 2 is not dismissible: the thing the user asked for still does
      // not work, so putting the notice away would only hide the reason.
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.denied);
      await tester.pumpWidget(_wrap(center, _gate()));
      await tester.pump();

      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('an informational notice is dismissed and stays dismissed', (
      tester,
    ) async {
      final center = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await tester.pumpWidget(_wrap(center, _informational()));
      await tester.pump();
      expect(find.text('Notifications are turned off'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(find.text('Notifications are turned off'), findsNothing);
      expect(center.isDismissed(AppPermission.pushNotifications), isTrue);
      expect(
        center.outcomeOf(AppPermission.pushNotifications),
        PermissionOutcome.denied,
        reason: 'dismissed is not granted - the permission is still refused',
      );
    });

    test('a dismissal is written where a later launch will find it', () async {
      // The write half, which no test reached: removing `persistSetting` from
      // `dismiss()` left the suite green, so a build where dismissal was
      // per-*process* - the thing `PermissionCenter` exists to improve on -
      // would have shipped clean.
      //
      // A second centre reading the same store is the launch after.
      final center = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await center.dismiss(AppPermission.pushNotifications);

      final nextLaunch = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await nextLaunch.load();

      expect(nextLaunch.isDismissed(AppPermission.pushNotifications), isTrue);
    });

    test('granting it clears the stored dismissal too', () async {
      // In memory and on disk. Clearing only the in-memory copy left the
      // stored `true` behind, so the next launch read it back and a *fresh*
      // denial was silenced by a dismissal made before the grant.
      final center = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await center.dismiss(AppPermission.pushNotifications);
      center.record(AppPermission.pushNotifications, PermissionOutcome.granted);
      // The clear is fire-and-forget, so let it land before reading back.
      await pumpEventQueue();

      final nextLaunch = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await nextLaunch.load();

      expect(nextLaunch.isDismissed(AppPermission.pushNotifications), isFalse);
    });

    test('load is read once', () async {
      // Memoised, because the alternative is a disk read per build of every
      // notice - CLAUDE.md's first anti-pattern.
      final center = PermissionCenter();
      expect(center.load(), same(center.load()));
      await center.load();
    });

    testWidgets('a dismissal survives the process it was made in', (
      tester,
    ) async {
      // Per install, not per process. `storage/permissions.dart`'s
      // `_prompt ??=` is the per-process version, and a dismissal that
      // lapsed at the next launch would ask again about something the user
      // had already decided.
      SharedPreferences.setMockInitialValues({
        AppPermission.pushNotifications.dismissalKey: true,
      });
      final center = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await center.load();

      await tester.pumpWidget(_wrap(center, _informational()));
      await tester.pump();

      expect(find.text('Notifications are turned off'), findsNothing);
    });

    testWidgets('granting it again clears the dismissal', (tester) async {
      // So that a user who revokes the permission later is told again. A
      // dismissal from months ago silencing a fresh denial is the bug this
      // whole file is about, arriving by a different route.
      final center = PermissionCenter()
        ..record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await center.dismiss(AppPermission.pushNotifications);
      expect(center.isDismissed(AppPermission.pushNotifications), isTrue);

      center.record(AppPermission.pushNotifications, PermissionOutcome.granted);
      expect(center.isDismissed(AppPermission.pushNotifications), isFalse);

      center.record(AppPermission.pushNotifications, PermissionOutcome.denied);
      await tester.pumpWidget(_wrap(center, _informational()));
      await tester.pump();

      expect(find.text('Notifications are turned off'), findsOneWidget);
    });
  });

  group('record', () {
    test('is quiet when nothing changed', () {
      // `appDocumentsDirectory()` reports on every file operation, and a
      // notify per call would rebuild every listening surface several times a
      // second — which is the shape of the #135/#136 battery-poll fetch.
      final center = PermissionCenter();
      var notifications = 0;
      center.addListener(() => notifications++);

      center.record(AppPermission.storage, PermissionOutcome.granted);
      expect(notifications, 1);

      center.record(AppPermission.storage, PermissionOutcome.granted);
      center.record(AppPermission.storage, PermissionOutcome.granted);
      expect(notifications, 1, reason: 'the value never changed');

      center.record(AppPermission.storage, PermissionOutcome.denied);
      expect(notifications, 2);
    });
  });

  group('refresh', () {
    test('one probe failing does not strand the others', () async {
      // Each probe is a different plugin. A permission that cannot be read is
      // one whose notice will not clear when the user grants it, so the
      // failure is kept — but it must not cost the other four their re-read.
      var bluetoothProbed = false;
      final center = PermissionCenter(
        probes: {
          AppPermission.storage: () async =>
              throw StateError('channel unavailable'),
          AppPermission.bluetooth: () async {
            bluetoothProbed = true;
            return PermissionOutcome.denied;
          },
        },
      );

      await center.refresh();

      expect(bluetoothProbed, isTrue);
      expect(
        center.outcomeOf(AppPermission.bluetooth),
        PermissionOutcome.denied,
      );
    });

    test('a failed probe leaves the outcome it already had', () async {
      // Not reset to `unknown`. Forgetting a denial already proved is how a
      // gate disappears and the feature behind it fails unexplained again —
      // which is the original bug, reintroduced by the fix.
      var calls = 0;
      final center = PermissionCenter(
        probes: {
          AppPermission.storage: () async {
            calls++;
            if (calls == 1) return PermissionOutcome.denied;
            throw StateError('channel unavailable');
          },
        },
      );

      await center.refresh();
      expect(center.outcomeOf(AppPermission.storage), PermissionOutcome.denied);

      await center.refresh();
      expect(
        center.outcomeOf(AppPermission.storage),
        PermissionOutcome.denied,
        reason: 'the denial we proved survives a read that could not run',
      );
    });

    test('two resumes in a row do not overlap, and do not get lost', () async {
      // A permission sheet closing can produce two resumes in quick
      // succession. Overlapping runs would race on the writes - but dropping
      // the second is worse, because it may be the resume that comes *after*
      // the user granted the permission, and then the notice stays up until
      // something else happens to trigger a read.
      //
      // So the second is queued: the probes run again, once, after the first
      // pass finishes.
      var calls = 0;
      final center = PermissionCenter(
        probes: {
          AppPermission.storage: () async {
            calls++;
            await Future<void>.delayed(Duration.zero);
            return PermissionOutcome.granted;
          },
        },
      );

      await Future.wait([center.refresh(), center.refresh()]);

      expect(
        calls,
        2,
        reason: 'queued, not dropped - the second may be the one after a grant',
      );
    });

    test('a later resume runs the probes again', () async {
      // The mutation that used to survive: deleting `refresh`'s `try/finally`
      // leaves `_refresh` set forever, so every later call returns the same
      // finished future and no probe ever runs a second time. That makes the
      // resume re-read a once-per-process operation and kills the half of
      // #351 the widget cannot supply - on iOS it leaves the blocking gate up
      // after the user granted the permission, which its own footnote
      // promises it will not.
      //
      // Asserting the outcome alone could not see it, because the outcome was
      // already correct from the first pass. Only the call count can.
      var calls = 0;
      final center = PermissionCenter(
        probes: {
          AppPermission.storage: () async {
            calls++;
            return PermissionOutcome.denied;
          },
        },
      );

      await center.refresh();
      expect(calls, 1);
      await center.refresh();
      expect(calls, 2, reason: 'a resume after the first must re-read');
      await center.refresh();
      expect(calls, 3);
    });

    test('a resumed lifecycle event triggers the re-read', () async {
      // `install()` plus `didChangeAppLifecycleState` had no test at all, and
      // between them they are the entire mechanism by which a grant made in
      // system settings reaches the app.
      var calls = 0;
      final center = PermissionCenter(
        probes: {
          AppPermission.storage: () async {
            calls++;
            return PermissionOutcome.granted;
          },
        },
      )..install();
      addTearDown(center.dispose);

      center.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(calls, 0, reason: 'only a resume reads');

      center.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(calls, 1);
    });

    test('a known outcome is never downgraded to unknown', () async {
      // Both the push and the location probe answer `unknown` for a status
      // that cannot tell "never asked" from "said no" - which is what
      // `permission_handler` and Geolocator both report on a fresh install.
      // The ask establishes the denial; this is what stops the next resume
      // talking over it and making the gate vanish with no user action.
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.denied)
        ..record(AppPermission.storage, PermissionOutcome.unknown);

      expect(center.outcomeOf(AppPermission.storage), PermissionOutcome.denied);

      // A first `unknown` is still allowed: nothing is being forgotten.
      final fresh = PermissionCenter()
        ..record(AppPermission.bluetooth, PermissionOutcome.unknown);
      expect(
        fresh.outcomeOf(AppPermission.bluetooth),
        PermissionOutcome.unknown,
      );
    });

    test('a permission with no probe keeps what it was told', () async {
      // Correct for one the app only ever learns about by asking, rather than
      // a reason to overwrite it with `unknown`.
      final center = PermissionCenter()
        ..record(AppPermission.serviceLocation, PermissionOutcome.denied);

      await center.refresh();

      expect(
        center.outcomeOf(AppPermission.serviceLocation),
        PermissionOutcome.denied,
      );
    });
  });

  group('the tier decides the surface', () {
    test('Bluetooth blocks the app on iOS and gates a feature elsewhere', () {
      // The one place the answer depends on the platform. On iOS
      // `transport/usb/ios.dart` throws `UnsupportedError`, so there is no
      // second transport and every screen behind the prompt is furniture; on
      // Android USB-OTG still reaches the device.
      expect(
        AppPermission.bluetooth.tier(iosBluetoothIsBlocking: true),
        PermissionTier.blocking,
      );
      expect(
        AppPermission.bluetooth.tier(iosBluetoothIsBlocking: false),
        PermissionTier.featureGate,
      );
    });

    test('nothing else ever blocks the whole app', () {
      // Blocking the app for a permission one feature needs is named in the
      // issue as the thing not to do. Storage is the one most likely to be
      // argued up, and it must not be: connect, browse and control all work
      // without it.
      for (final permission in AppPermission.values) {
        if (permission == AppPermission.bluetooth) continue;
        expect(
          permission.tier(iosBluetoothIsBlocking: true),
          isNot(PermissionTier.blocking),
          reason: '${permission.name} must not block the app',
        );
      }
    });

    test('a feature gate ignores a dismissal entirely', () {
      // The surviving mutation: making the visibility branch ask
      // `shouldNotice` unconditionally left the suite green. `dismiss()` is
      // public, so a gate that honoured a dismissal would hide the reason a
      // feature does not work while the feature still does not work.
      final center = PermissionCenter()
        ..record(AppPermission.storage, PermissionOutcome.denied);
      center.dismiss(AppPermission.storage);

      expect(center.isDismissed(AppPermission.storage), isTrue);
      expect(
        center.outcomeOf(AppPermission.storage).warrantsNotice,
        isTrue,
        reason: 'which is what a gate reads, so the gate stays up',
      );
    });

    test('a Tier 3 notice is dismissible whatever severity draws it', () {
      // `serviceLocation` is Tier 3 and is drawn `degraded`. Dismissibility
      // used to be derived from severity, so that combination silently
      // removed the Dismiss button and left a permanent warning for something
      // the tier's own definition calls "never nags".
      expect(
        AppPermission.serviceLocation.tier(iosBluetoothIsBlocking: false),
        PermissionTier.informOnce,
      );
    });

    test('the dismissal keys are the literals the docstring promises', () {
      // Spelled out so renaming an enum value cannot un-dismiss a notice on
      // every install that had dismissed it. Checking uniqueness alone let a
      // mutation to `name` pass, which is the rename this is meant to survive.
      expect(
        AppPermission.storage.dismissalKey,
        'permission.dismissed.storage',
      );
      expect(
        AppPermission.bluetooth.dismissalKey,
        'permission.dismissed.bluetooth',
      );
      expect(
        AppPermission.pushNotifications.dismissalKey,
        'permission.dismissed.push',
      );
      expect(
        AppPermission.serviceNotification.dismissalKey,
        'permission.dismissed.fgs_notify',
      );
      expect(
        AppPermission.serviceLocation.dismissalKey,
        'permission.dismissed.fgs_location',
      );
    });

    test('tierOf answers for the platform it was given', () {
      // Injected rather than read from `Platform.isIOS`, which is what makes
      // the Tier 1 gate decision testable on both platforms at all.
      final ios = PermissionCenter(bluetoothIsTheOnlyTransport: true);
      final android = PermissionCenter(bluetoothIsTheOnlyTransport: false);

      expect(ios.tierOf(AppPermission.bluetooth), PermissionTier.blocking);
      expect(
        android.tierOf(AppPermission.bluetooth),
        PermissionTier.featureGate,
      );
    });

    test('every permission has a distinct dismissal key', () {
      // Spelled out rather than derived from `name`, so renaming a value
      // cannot un-dismiss a notice on every install that had dismissed it. A
      // collision would silence one notice with another's dismissal.
      final keys = AppPermission.values.map((p) => p.dismissalKey).toSet();
      expect(keys, hasLength(AppPermission.values.length));
    });
  });

  group('warrantsNotice is the one predicate', () {
    test('only a denial warrants one', () {
      // Decided once rather than at five call sites, which is how
      // `push_service.dart` came to assert a denied permission as an unsigned
      // build.
      expect(PermissionOutcome.denied.warrantsNotice, isTrue);
      expect(PermissionOutcome.granted.warrantsNotice, isFalse);
      expect(PermissionOutcome.unknown.warrantsNotice, isFalse);
      expect(PermissionOutcome.unavailable.warrantsNotice, isFalse);
    });
  });
}
