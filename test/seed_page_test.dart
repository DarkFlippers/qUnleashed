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
import 'package:qunleashed/components/path.dart';
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

      // The list itself, not just the invariant prose. The whole point of the
      // `{chars}` placeholder is that the sentence cannot drift from
      // `reservedNameChars`, and matching only "cannot contain" leaves the
      // argument unobservable - a hardcoded, wrong list passes it.
      expect(
        find.textContaining('cannot contain $reservedNameCharsSpelled'),
        findsOneWidget,
      );
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

    testWidgets('writes under the name that was typed, not the suggestion', (
      tester,
    ) async {
      // The one path the feature exists for, and nothing covered it: every
      // other test here confirms the suggestion unchanged, so
      // `_controller.save(suggested)` in place of `save(chosen)` passed the
      // whole file. Extracting the dialog made this worse rather than better -
      // `QNameDialog` now has its own suite proving it *returns* the typed
      // name, and that is not the same as the page using what it returns.
      //
      // It also pins the suffix contract end to end: the field holds a base
      // name, the caller appends `.sub`, and the result is not `gate.sub.sub`.
      final client = SeedFakeClient();
      await _openPage(tester, client);
      await tester.tap(find.text('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover Seed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Flipper'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'kitchen gate');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save to Flipper'));
      await tester.pumpAndSettle();

      expect(client.writes.keys, ['/ext/subghz/kitchen gate.sub']);
    });

    testWidgets('names a dotted name as a dot problem, not a length one', (
      tester,
    ) async {
      // Half the mapping was pinned: sending `tooLong` to the dot sentence
      // fails the test below, but sending `dotEdge` to the length sentence
      // passed, because nothing here ever typed a dotted name. An exhaustive
      // switch buys totality, not a correct pairing.
      final client = SeedFakeClient();
      await _openPage(tester, client);
      await tester.tap(find.text('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover Seed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Flipper'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '.gate');
      await tester.pump();

      expect(find.textContaining('start or end with a dot'), findsOneWidget);
      expect(find.textContaining('shorter name'), findsNothing);
    });

    testWidgets('says something a user can act on about a pasted newline', (
      tester,
    ) async {
      // A control character cannot be listed in the nine, so before this it
      // was reported with a sentence naming nine characters the user had not
      // typed. A keyboard cannot produce one; a paste can.
      final client = SeedFakeClient();
      await _openPage(tester, client);
      await tester.tap(find.text('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover Seed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Flipper'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'gate\tone');
      await tester.pump();

      expect(find.textContaining('invisible character'), findsOneWidget);
      expect(
        find.textContaining(reservedNameCharsSpelled),
        findsNothing,
        reason: 'the nine are not what is wrong with this name',
      );
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

      // The prose rather than the number: the helper text under the field
      // names the limit too, so `63` appears twice and matching it would pass
      // whether or not the error ever appeared.
      expect(find.textContaining('shorter name'), findsOneWidget);
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save to Flipper'),
      );
      expect(save.onPressed, isNull);
    });
  });

  group('the row delete', () {
    // The row button is the only way to reach a capture that cannot be solved,
    // so it is also the only way to destroy one. Everything below is about
    // which file goes and on whose say.

    Future<void> openTwo(WidgetTester tester, SeedFakeClient client) async {
      client.folder['one.txt'] = seedCaptureFixture;
      client.folder['two.txt'] = seedCaptureFixture;
      await _openPage(tester, client);
    }

    /// The trash icon on the row titled [name].
    Finder trashOn(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
      matching: find.byIcon(Icons.delete_outline),
    );

    testWidgets('deletes the row it was tapped on, not the first', (
      tester,
    ) async {
      // The controller tests all call deleteCapture(file) directly, so they
      // cannot see the page handing over the wrong file. With two captures
      // listed, `files.first` instead of `file` destroys the wrong one and
      // every one of them still passes.
      final client = SeedFakeClient();
      await openTwo(tester, client);

      // Newest first, so two.txt is the top row and one.txt the second.
      await tester.tap(trashOn('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete Capture'));
      await tester.pumpAndSettle();

      expect(client.folder.keys, ['two.txt']);
      expect(find.text('one.txt'), findsNothing);
      expect(find.text('two.txt'), findsOneWidget);
    });

    testWidgets('Cancel leaves the capture alone', (tester) async {
      // The other half of the one-character guard this file exists for, on the
      // dialog the row opens - which uses `commonCancel` rather than the
      // post-save prompt's "Keep It".
      final client = SeedFakeClient();
      await openTwo(tester, client);

      await tester.tap(trashOn('one.txt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('only record of a remote'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(client.folder.keys, containsAll(['one.txt', 'two.txt']));
      expect(find.text('one.txt'), findsOneWidget);
    });

    testWidgets('the prompt names the file being deleted', (tester) async {
      // Both dialogs share a title, so the name in the body is the only thing
      // telling the user which capture they are about to lose.
      final client = SeedFakeClient();
      await openTwo(tester, client);

      await tester.tap(trashOn('two.txt'));
      await tester.pumpAndSettle();

      expect(find.textContaining('two.txt'), findsWidgets);
    });

    testWidgets('is disabled when the rows outlived their link', (
      tester,
    ) async {
      // A delete sent under a dead binding fails rather than reaching another
      // Flipper, but the page should not offer it at all - and should say what
      // to do instead rather than greying out in silence.
      final client = SeedFakeClient()..connected = false;
      await openTwo(tester, client);

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: trashOn('one.txt'),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('pull to refresh', () {
    testWidgets('does not run while a search is going', (tester) async {
      // A pull used to overwrite SeedStage.searching: the progress bar and
      // Stop went away while the sweep ran on, Start came back enabled, and
      // PopScope let the page pop without the stop confirmation. The toolbar
      // button has always been guarded; a RefreshIndicator cannot be, so the
      // guard has to live in the handler.
      final client = SeedFakeClient()..folder['one.txt'] = seedCaptureFixture;
      final engine = SlowRecoverer.gate();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
          home: SeedPage(client: client, recoverer: engine),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('one.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover Seed'));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget, reason: 'the search is on');
      client.calls.clear();

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        client.calls.where((c) => c.startsWith('list(')),
        isEmpty,
        reason: 'the folder must not be re-listed mid-search',
      );
      expect(
        find.text('Stop'),
        findsOneWidget,
        reason: 'the search must still be stoppable',
      );

      engine.finish();
      await tester.pumpAndSettle();
    });
  });
}
