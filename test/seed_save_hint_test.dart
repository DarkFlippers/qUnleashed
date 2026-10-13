// What the page says when the Save button is not there.
//
// The other half of #294. `test/seed_save_block_test.dart` pins which refusal
// the controller reports; this pins that each one reaches the screen as a
// sentence, because the bug was never in the gate - it was that an answer
// missing a field was explained nowhere, and the user was left with a card
// that said "Seed recovered", no button, and nothing to act on.
//
// The engine is injected for the reason `seed_page_test.dart` gives: a real
// search in a widget test comes back `engineUnavailable`, the answer is then
// never `found`, and every case below would collapse into the same one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/subghz/seed/faaccrack_recoverer.dart';
import 'package:qunleashed/pages/tools/subghz/seed/seed_page.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

import 'seed_fakes.dart';

/// Opens one capture and recovers it, leaving the result card on screen.
Future<void> _recover(
  WidgetTester tester, {
  required String capture,
  required FaaccrackRecoverer recoverer,
}) async {
  final client = SeedFakeClient()..folder['one.txt'] = capture;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      // The page reads the app's colour extension, so a bare MaterialApp
      // renders it as a null check on a missing theme.
      theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
      home: SeedPage(client: client, recoverer: recoverer),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('one.txt'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Recover Seed'));
  await tester.pumpAndSettle();
}

final _save = find.widgetWithText(FilledButton, 'Save to Flipper');
final _lowConfidence = find.textContaining('Backed by only');
final _noFrequency = find.textContaining('This capture has no frequency');
final _brokenEngine = find.textContaining('Nothing you do with this capture');

void main() {
  testWidgets('an answer that can be saved gets the button and no hint', (
    tester,
  ) async {
    await _recover(
      tester,
      capture: seedCaptureFixture,
      recoverer: FoundRecoverer(),
    );

    expect(_save, findsOneWidget);
    // Usable, not merely built: `findsOneWidget` matches a disabled button
    // just as well, and "the button is there" is what this test is named for.
    expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    expect(_lowConfidence, findsNothing);
    expect(_noFrequency, findsNothing);
    expect(_brokenEngine, findsNothing);
  });

  testWidgets('a capture with no frequency says so, and offers no Save', (
    tester,
  ) async {
    await _recover(
      tester,
      capture: seedCaptureNoFrequency,
      recoverer: FoundRecoverer(),
    );

    expect(_noFrequency, findsOneWidget);
    expect(_save, findsNothing);
  });

  testWidgets('an answer under the confidence line says how many hops', (
    tester,
  ) async {
    await _recover(
      tester,
      capture: seedCaptureTwoHops,
      recoverer: FoundRecoverer(),
    );

    // The count, not just the sentence: it is the figure the user decides on.
    expect(find.textContaining('Backed by only 2 hops'), findsOneWidget);
    expect(_save, findsNothing);
  });

  testWidgets('an answer missing a field is not announced as a seed', (
    tester,
  ) async {
    // The state #294 was filed about. The card used to headline "Seed
    // recovered" over no figures, no button and no sentence; the answer never
    // reaches the page as `found` now, so the headline is the engine's fault
    // and the hint says nothing the user does with this capture will help.
    await _recover(
      tester,
      capture: seedCaptureFixture,
      recoverer: IncompleteRecoverer(hopsUsed: null),
    );

    expect(find.text('Seed recovered'), findsNothing);
    expect(find.text('The recovery engine failed'), findsOneWidget);
    expect(_brokenEngine, findsOneWidget);
    expect(_save, findsNothing);
    // And not "backed by only 0 hops", which is what reporting a missing hop
    // count as the confidence refusal would have put on screen.
    expect(_lowConfidence, findsNothing);
  });

  testWidgets('an unverified answer is not also blamed on its hop count', (
    tester,
  ) async {
    // Deliberate, and a change: the page used to show the confidence sentence
    // for any shown seed, so a two-hop unverified answer was refused "because"
    // of its hops when the frame being unbuildable is the reason - and the
    // sentence it printed, "it is not offered for transmission", named the
    // wrong cause. The unverified hint is the accurate one - and it carries
    // the advice the dropped sentence had, since a longer capture is what lets
    // the engine reject a seed it could not verify. The *capture's* hop count
    // is on the card above, which is the same figure here and need not be.
    await _recover(
      tester,
      capture: seedCaptureTwoHops,
      recoverer: UnverifiedRecoverer(),
    );

    // The seed is on screen, which is what makes this the state the dropped
    // sentence used to fire in - and what a fake answering with every field
    // null could not build.
    expect(find.text('Seed'), findsOneWidget);
    expect(
      find.textContaining('The seed is shown for reference'),
      findsOneWidget,
    );
    // The advice, which is the half of the dropped sentence worth keeping:
    // more hops is what lets the engine reject a seed it could not verify, and
    // this hint is the one this path shows.
    expect(
      find.textContaining('press the remote a few more times'),
      findsOneWidget,
    );
    expect(_lowConfidence, findsNothing);
    // Nor on anything else. `notFound` is the arm with nothing to add, so a
    // sentence here would be a second, wrong explanation beside the hint that
    // is already right.
    expect(_brokenEngine, findsNothing);
    expect(_noFrequency, findsNothing);
    expect(_save, findsNothing);
  });
}
