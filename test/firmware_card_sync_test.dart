import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/config.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_card.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_changelog_page.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_update_button.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/notifications/push_intent.dart';
import 'package:qunleashed/services/notifications/push_service.dart';
import 'package:qunleashed/theme/theme.dart';

import 'firmware_fixture.dart';

/// What moves the firmware carousel, and what must not — #135.
///
/// The card used to sync from `didUpdateWidget`, which the parent supplies a
/// new widget for on every rebuild. `DeviceScope` is an `InheritedNotifier`
/// driven by a five-second battery poll, so with a device connected that ran
/// twelve times a minute: an `ensureDirectory` call each time - free while the
/// directory is fresh, a fresh request once a failed fetch has left nothing
/// cached - and a `jumpToPage` scheduled on top of whatever the carousel
/// arrows were animating.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final theme = QAppThemeController.instance;
  late DeviceController device;

  setUp(() {
    resetFirmwareState();
    (device, _) = mountedDevice();
  });

  /// Which firmware the card is showing.
  ///
  /// Read from the update button rather than from a slide's name: the button
  /// is built once, outside the carousel, from the entry the page resolves
  /// to, so it answers without depending on what the viewport has built.
  String shown(WidgetTester tester) => tester
      .widget<FirmwareUpdateButton>(find.byType(FirmwareUpdateButton))
      .entry
      .shortName;

  /// Where the carousel itself is, as a page offset.
  ///
  /// [shown] answers what the controls are pointed at; this answers what the
  /// user is looking at. They are set by different lines, and a test that
  /// reads only the first cannot tell that the view stayed behind.
  double? carouselPage(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page;

  Future<void> pumpCard(WidgetTester tester, {String? deviceVersion}) async {
    await tester.pumpWidget(
      wrapWithDevice(
        FirmwareCard(deviceVersion: deviceVersion, deviceInfo: const {}),
        device,
      ),
    );
    await tester.pump();
  }

  // The card's fallback for a firmware outside the config cannot be reached
  // from a test, because this is what stops one getting in. Asserted at the
  // owner rather than checked at the two writers - `_followPage` here and
  // `syncFirmwareFromDeviceInfo` on the device stream.
  test('the theme refuses a firmware outside the config', () {
    expect(
      () => theme.setActiveFirmware(
        const FirmwareEntry(
          name: 'Nope',
          shortName: 'nope',
          icon: 'nope.png',
          colors: FirmwareColors(
            primary: Color(0xFF000000),
            secondary: Color(0xFF000000),
            tertiary: Color(0xFF000000),
          ),
        ),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  // The card resolves its page from the theme rather than from the page
  // controller's initial one, so a mount onto a theme that has already moved
  // has to bring the carousel across too, not just the controls.
  testWidgets('the card opens on the firmware already active', (tester) async {
    theme.setActiveFirmware(official);

    await pumpCard(tester);
    await tester.pump();

    expect(shown(tester), official.shortName);
    expect(carouselPage(tester), 1.0);

    await closeDevice(tester, device);
  });

  // Picking a firmware is what re-themes the app - accent and brightness both
  // resolve from the active firmware - so a swipe that moves the page without
  // telling the controller leaves one firmware's card under another's colours.
  testWidgets('moving the carousel re-themes the app', (tester) async {
    await pumpCard(tester);
    await tester.pump();
    expect(theme.activeFirmware.shortName, unleashed.shortName);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(theme.activeFirmware.shortName, official.shortName);

    await closeDevice(tester, device);
  });

  testWidgets('the arrows walk both ways', (tester) async {
    await pumpCard(tester);
    await tester.pump();

    expect(
      tester
          .widget<InkWell>(
            find.ancestor(
              of: find.byIcon(Icons.chevron_left),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
      reason: 'nothing to the left of the first page',
    );

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(shown(tester), official.shortName);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(shown(tester), unleashed.shortName);
    expect(carouselPage(tester), 0.0);

    await closeDevice(tester, device);
  });

  // The fetch half of #135. A rebuild carrying a new battery reading says
  // nothing about which firmware is on screen, so it must not go to the
  // network.
  testWidgets('a parent rebuild does not fetch a directory', (tester) async {
    await pumpCard(tester, deviceVersion: '1.0.0');
    await tester.pump();
    expect(
      fetchCalls,
      2,
      reason: 'the controller prefetched both firmwares on construction',
    );

    forgetDirectories();
    final afterFirstBuild = fetchCalls;

    // What the five-second battery poll does: same card, new props.
    for (var i = 0; i < 5; i++) {
      await pumpCard(tester, deviceVersion: '1.0.$i');
    }

    expect(fetchCalls, afterFirstBuild);

    await closeDevice(tester, device);
  });

  // The listener that replaced it still has to do the job it was there for.
  testWidgets('the card follows the firmware the theme moved to', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.pump();

    expect(shown(tester), unleashed.shortName);

    theme.setActiveFirmware(official);
    await tester.pumpAndSettle();

    expect(shown(tester), official.shortName);
    expect(
      carouselPage(tester),
      1.0,
      reason: 'the view followed too, not just the controls',
    );

    await closeDevice(tester, device);
  });

  // The theme controller notifies for more than the active firmware, and the
  // card is only interested in that one.
  testWidgets('a theme mode change does not fetch a directory', (tester) async {
    await pumpCard(tester);
    await tester.pump();
    forgetDirectories();
    final afterFirstBuild = fetchCalls;

    await theme.setThemeMode(QThemeMode.light);
    await tester.pump();
    await theme.setThemeMode(QThemeMode.dark);
    await tester.pump();

    expect(fetchCalls, afterFirstBuild);

    await closeDevice(tester, device);
  });

  // The other half of #135: the arrows animate over 220ms, and the sync that
  // used to run every five seconds scheduled a jumpToPage across it. The same
  // thing happens if the card's own page-change notify re-enters the sync,
  // which is what the [_page]-before-[_followPage] ordering prevents.
  testWidgets('an arrow animation is not cut short by the sync', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chevron_right));
    // tap() does not pump, so this first frame is what starts the ticker -
    // without it the elapse below lands at animation time zero and the
    // assertion reads a page that has not moved yet.
    await tester.pump();
    // Past halfway, so onPageChanged has fired and its notify has been
    // answered - and the answer is the early return, so no jump was ever
    // scheduled. That absence is what this pins. Well short of the 220ms end,
    // and the first assertion below checks the past-halfway half rather than
    // assuming it.
    await tester.pump(const Duration(milliseconds: 48));

    expect(
      shown(tester),
      official.shortName,
      reason: 'past halfway, so onPageChanged has fired and been answered',
    );
    expect(
      carouselPage(tester),
      lessThan(1.0),
      reason: 'still travelling, not snapped to the destination',
    );

    await tester.pumpAndSettle();
    expect(shown(tester), official.shortName);

    await closeDevice(tester, device);
  });

  // The card repaints on the controller's own notify, which is how a
  // directory arriving replaces "Checking…" with a version. Without it the
  // card holds the loading text for the session - #118's symptom, one layer
  // up from where #118 fixed it.
  testWidgets('a directory arriving repaints the card', (tester) async {
    final gate = Completer<Map<String, dynamic>>();
    forgetDirectories();
    feedEvery((_) => gate.future);

    await pumpCard(tester);
    await tester.pump();
    expect(find.text(l10n.firmwareChecking), findsWidgets);

    gate.complete(feedJson());
    await tester.pumpAndSettle();

    expect(find.text(l10n.firmwareChecking), findsNothing);

    await closeDevice(tester, device);
  });

  group('a push notification tap', () {
    // The card defers the changelog until the directory lands. Opening it
    // early finds no version, clears the pending intent anyway, and leaves
    // the user with a tap that did nothing and cannot be repeated - the
    // failure that got #118's retry cooldown reverted.
    testWidgets('waits for the directory before opening the changelog', (
      tester,
    ) async {
      final gate = Completer<Map<String, dynamic>>();
      forgetDirectories();
      feedEvery((_) => gate.future);

      await pumpCard(tester);
      await tester.pump();

      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'unlshd',
      );
      await tester.pump();

      expect(find.byType(FirmwareChangelogPage), findsNothing);
      expect(
        PushService.instance.taps.value,
        isNotNull,
        reason: 'still pending, not consumed',
      );

      gate.complete(feedJson());
      await tester.pumpAndSettle();

      expect(find.byType(FirmwareChangelogPage), findsOneWidget);
      expect(
        PushService.instance.taps.value,
        isNull,
        reason: 'spent, or the next card to mount opens it again',
      );

      await closeDevice(tester, device);
    });

    // A push announces a firmware the user is not looking at - that is what
    // it is for - so the card has to move there.
    testWidgets('for the other firmware moves the carousel', (tester) async {
      // A feed with no versions: the move is what this is about, and a
      // changelog route pushed over the card hides the carousel offstage -
      // carouselPage then finds no PageView, and shown reads the changelog's
      // own update button instead of the card's.
      feedEvery((_) async => <String, dynamic>{'channels': <dynamic>[]});

      await pumpCard(tester);
      await tester.pump();
      expect(shown(tester), unleashed.shortName);

      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'ofw',
      );
      await tester.pumpAndSettle();

      expect(shown(tester), official.shortName);
      expect(carouselPage(tester), 1.0);

      await closeDevice(tester, device);
    });

    // The changelog that opens has to be the one the push named, not
    // whichever firmware happened to be first.
    testWidgets('opens the changelog for the firmware it named', (
      tester,
    ) async {
      await pumpCard(tester);
      await tester.pump();

      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'ofw',
      );
      await tester.pumpAndSettle();

      final page = tester.widget<FirmwareChangelogPage>(
        find.byType(FirmwareChangelogPage),
      );
      expect(page.entry.shortName, official.shortName);

      await closeDevice(tester, device);
    });

    // The tap is spent and nothing is on screen, so the log line is the only
    // record it happened - and the repository will usually have said nothing,
    // because its own suppression drops a repeat of the prefetch's reason.
    testWidgets('that cannot be answered is dropped, and said', (tester) async {
      feedFails();

      await pumpCard(tester);
      await tester.pump();

      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'unlshd',
      );
      await tester.pumpAndSettle();

      expect(find.byType(FirmwareChangelogPage), findsNothing);
      expect(PushService.instance.taps.value, isNull);
      final kept = keptAbout('push tap for unlshd dropped');
      expect(kept, hasLength(1));
      expect(kept.single, contains('could not be fetched'));

      await closeDevice(tester, device);
    });

    // The app opened from the notification: the intent is already in the
    // notifier before the card exists, and the post-frame callback in
    // initState is the only thing that reads it.
    testWidgets('that arrived before the card did is still answered', (
      tester,
    ) async {
      feedEvery((_) async => <String, dynamic>{'channels': <dynamic>[]});
      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'ofw',
      );

      await pumpCard(tester);
      await tester.pumpAndSettle();

      expect(shown(tester), official.shortName);
      expect(carouselPage(tester), 1.0);

      await closeDevice(tester, device);
    });

    // A tap still waiting for its directory when a second arrives is the
    // third way one can end without a changelog, and the other two say so.
    testWidgets('superseded before its directory landed is said', (
      tester,
    ) async {
      final gate = Completer<Map<String, dynamic>>();
      forgetDirectories();
      feedEvery((_) => gate.future);

      await pumpCard(tester);
      await tester.pump();

      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'unlshd',
      );
      await tester.pump();
      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'ofw',
      );
      await tester.pump();

      final kept = keptAbout('superseded by');
      expect(kept, hasLength(1));
      expect(kept.single, contains('unlshd'));

      gate.complete(feedJson());
      await tester.pumpAndSettle();
      await closeDevice(tester, device);
    });

    testWidgets('for a firmware that is not configured is dropped', (
      tester,
    ) async {
      await pumpCard(tester);
      await tester.pump();

      PushService.instance.taps.value = const PushIntent(
        type: PushIntent.typeFirmware,
        entry: 'not-a-firmware',
      );
      await tester.pumpAndSettle();

      expect(find.byType(FirmwareChangelogPage), findsNothing);
      expect(
        PushService.instance.taps.value,
        isNull,
        reason: 'consumed, so it cannot be retried on every later notify',
      );
      final kept = keptAbout('push names an unknown firmware');
      expect(kept, hasLength(1), reason: 'consumed, but not in silence');
      expect(kept.single, contains('not-a-firmware'));

      await closeDevice(tester, device);
    });

    testWidgets('for an app release is left alone', (tester) async {
      await pumpCard(tester);
      await tester.pump();

      // Left set on purpose: this card is not the one to spend it. Nothing
      // clears it afterwards - this is the last test in the file - and the
      // notifier is process-wide, so it only stays harmless because each test
      // file gets its own isolate.
      const intent = PushIntent(type: PushIntent.typeApp, entry: 'unlshd');
      PushService.instance.taps.value = intent;
      await tester.pumpAndSettle();

      expect(find.byType(FirmwareChangelogPage), findsNothing);
      expect(
        PushService.instance.taps.value,
        same(intent),
        reason: 'not this card to consume',
      );

      await closeDevice(tester, device);
    });
  });
}
