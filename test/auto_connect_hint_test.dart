import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/dialogs/connection_error.dart';
import 'package:qunleashed/pages/devices/widgets/cards/auto_connect_hint.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_autoconnect_test.dart' show FakeDialClient, usb;

/// The card the device page shows after an auto-connect nobody watched.
///
/// The service half is in `link_autoconnect_test.dart`; this is what a user
/// sees. The two things worth pinning: that it says the cause rather than
/// "could not connect", and that the close button actually ends it - a hint
/// that cannot be put away is worse than none, because the condition it
/// describes can last the rest of the session.
///
/// Two things about the harness, both of which this file got wrong first:
///
///  * `LinkService` debounces its reconcile on a real `Timer`, and a
///    `testWidgets` body runs under a fake clock that never reaches it. The
///    service is therefore built and driven inside [WidgetTester.runAsync].
///  * That timer is also still pending when the body ends, and the binding
///    checks for live timers *before* `tearDown` runs - so the service is
///    disposed in the body, the same way `closeDevice` does it in
///    `firmware_fixture.dart`. Which means the tree is gone by the time
///    `expect` runs, and a `Finder` resolves then: each case reads the tree
///    into a bool first and asserts on that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDialClient client;

  setUp(() {
    client = FakeDialClient();
    addTearDown(() async => client.close());
  });

  /// A started service, with the stores it reads reset for this case.
  Future<LinkService> started(
    WidgetTester tester, {
    Object? refusedWith,
  }) async {
    late LinkService links;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(const {});
      final settings = DeviceSettings.instance..reset();
      await settings.load();
      await settings.setAutoConnectUsb(refusedWith != null);
      await KnownDevicesStore.instance.load();

      links = LinkService.forTest(client);
      if (refusedWith != null) {
        client.present = [usb('A')];
        client.connectThrows = refusedWith;
        client.plugged();
      }
      // Covers the debounce and the reconcile behind it, and leaves no timer
      // for the binding to find.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    return links;
  }

  /// How many times [text] is in the tree *now*, since the tree is torn down
  /// before the assertions run.
  int shown(String text) => find.text(text).evaluate().length;

  Future<void> close(WidgetTester tester, LinkService links) async {
    await tester.pumpWidget(const SizedBox());
    links.dispose();
  }

  Widget wrap(LinkService links) => MaterialApp(
    theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
    home: Scaffold(body: AutoConnectHintCard(links: links)),
  );

  testWidgets('is absent while nothing has failed', (tester) async {
    final links = await started(tester);

    await tester.pumpWidget(wrap(links));
    final found = shown(l10n.fmAutoConnectFailedTitle('A'));
    await close(tester, links);

    expect(found, 0);
  });

  testWidgets('names the Flipper it could not reach', (tester) async {
    final links = await started(tester, refusedWith: StateError('port busy'));

    await tester.pumpWidget(wrap(links));
    final found = shown(l10n.fmAutoConnectFailedTitle('A'));
    await close(tester, links);

    expect(found, 1);
  });

  // The whole reason the mapping is shared with the dialog: the session cap
  // is the case where "connection failed" is useless and "disconnect one
  // first" is the entire answer. #120.
  testWidgets('says what the picker would have said', (tester) async {
    final links = await started(
      tester,
      refusedWith: StateError(FlipperClient.sessionLimitMessage),
    );
    final (_, body) = describeConnectError(
      FlipperConnectErrorKind.sessionLimit,
      isBle: false,
    );

    await tester.pumpWidget(wrap(links));
    final found = shown(body);
    await close(tester, links);

    expect(found, 1);
  });

  testWidgets('goes away when closed', (tester) async {
    final links = await started(tester, refusedWith: StateError('port busy'));
    await tester.pumpWidget(wrap(links));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    final found = shown(l10n.fmAutoConnectFailedTitle('A'));
    final cleared = links.autoConnectFailure == null;
    await close(tester, links);

    expect(found, 0);
    expect(cleared, isTrue);
  });
}
