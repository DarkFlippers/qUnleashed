// The page's own chain: name the file, answer the overwrite prompt, answer the
// delete prompt.
//
// This exists for two one-character bugs. `if (!replace || !mounted) return;`
// and `if (!remove || !mounted) return;` are the whole of the user's say over
// two irreversible acts - overwriting a `.sub` they recorded by hand, and
// deleting the only copy of a capture they had to stand next to a remote to
// take. Dropping either `!` inverts the dialog, and nothing else in the repo
// would notice: the controller is happy either way, because by then it has
// been told to go ahead.
//
// The engine is injected. A real search in a widget test comes back
// `engineUnavailable` because the native library is not loaded, `canSave` is
// then false, and the Save button is never built - so the whole chain would be
// unreachable from here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_page.dart';

import 'seed_fakes.dart';

Future<void> _openPage(WidgetTester tester, SeedFakeClient client) async {
  // The page builds its own controller, so the folder has to be there before
  // it lists - unlike the controller tests, which go through a helper.
  if (client.folder.isEmpty) client.folder['one.txt'] = seedCaptureFixture;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      // The page reads the app's colour extension, so a bare MaterialApp
      // renders it as a null check on a missing theme.
      theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
      home: SeedPage(client: client, recoverer: FoundRecoverer()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Walks capture -> recover -> Save -> accept the suggested name.
Future<void> _recoverAndPressSave(
  WidgetTester tester,
  SeedFakeClient client,
) async {
  await _openPage(tester, client);

  await tester.tap(find.text('one.txt'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Recover Seed'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save to Flipper'));
  await tester.pumpAndSettle();

  // The name dialog, taking the suggestion unchanged.
  expect(find.text('Name the File'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'Save to Flipper'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saves under the suggested name and offers the capture', (
    tester,
  ) async {
    final client = SeedFakeClient();
    await _recoverAndPressSave(tester, client);

    expect(client.writes.keys, ['/ext/subghz/Genius_A0DC9330.sub']);
    expect(find.text('Delete the Capture?'), findsOneWidget);
  });

  group('the overwrite prompt', () {
    testWidgets('Cancel leaves the standing file alone', (tester) async {
      final client = SeedFakeClient()
        ..existing.add('/ext/subghz/Genius_A0DC9330.sub');
      await _recoverAndPressSave(tester, client);

      expect(find.text('Replace File?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        client.writes,
        isEmpty,
        reason: 'Cancel must not overwrite the file',
      );
      expect(find.text('Delete the Capture?'), findsNothing);
    });

    testWidgets('Replace writes over it', (tester) async {
      final client = SeedFakeClient()
        ..existing.add('/ext/subghz/Genius_A0DC9330.sub');
      await _recoverAndPressSave(tester, client);

      expect(find.text('Replace File?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Replace'));
      await tester.pumpAndSettle();

      expect(client.writes.keys, ['/ext/subghz/Genius_A0DC9330.sub']);
    });
  });

  group('the delete prompt', () {
    testWidgets('Keep It leaves the capture on the device', (tester) async {
      final client = SeedFakeClient();
      await _recoverAndPressSave(tester, client);

      expect(find.text('Delete the Capture?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep It'));
      await tester.pumpAndSettle();

      expect(
        client.folder,
        contains('one.txt'),
        reason: 'Keep It must not delete the capture',
      );
    });

    testWidgets('Delete Capture removes it', (tester) async {
      final client = SeedFakeClient();
      await _recoverAndPressSave(tester, client);

      await tester.tap(find.widgetWithText(TextButton, 'Delete Capture'));
      await tester.pumpAndSettle();

      expect(client.folder, isEmpty);
    });
  });

  group('the name dialog', () {
    testWidgets('refuses a name the rules reject, and says why', (
      tester,
    ) async {
      final client = SeedFakeClient();
      await _openPage(tester, client);
      await tester.tap(find.text('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover Seed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Flipper'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'bad/name');
      await tester.pump();

      expect(find.textContaining('cannot contain'), findsOneWidget);
      // Disabled rather than merely ignored, so the refusal is visible before
      // the press rather than as a banner after it.
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save to Flipper'),
      );
      expect(save.onPressed, isNull);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(client.writes, isEmpty);
    });

    testWidgets('a long name is refused, not silently shortened', (
      tester,
    ) async {
      // maxLength would have truncated this to 63 characters with nothing on
      // screen saying so, and written the file under a name the user did not
      // choose.
      final client = SeedFakeClient();
      await _openPage(tester, client);
      await tester.tap(find.text('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover Seed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Flipper'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'x' * 70);
      await tester.pump();

      expect(find.textContaining('at most'), findsOneWidget);
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save to Flipper'),
      );
      expect(save.onPressed, isNull);
    });
  });
}
