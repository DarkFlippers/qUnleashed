// What the page says when the Save button is not there.
//
// The other half of #294. `test/seed_save_block_test.dart` pins which refusal
// the controller reports; this pins that each one reaches the screen as a
// sentence, because the bug was never in the gate - it was that two of its
// four refusals were explained nowhere and the user was left with seed rows,
// no button and nothing to act on.
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
final _incomplete = find.textContaining(
  'came back without everything the file needs',
);

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
    expect(_lowConfidence, findsNothing);
    expect(_noFrequency, findsNothing);
    expect(_incomplete, findsNothing);
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

  group('a found answer with a field missing', () {
    // The pair #294 is named for. Each of these showed the seed rows, no
    // button, and no sentence anywhere.
    testWidgets('says the build is at fault when the seed is absent', (
      tester,
    ) async {
      await _recover(
        tester,
        capture: seedCaptureFixture,
        recoverer: IncompleteRecoverer(seed: null),
      );

      expect(_incomplete, findsOneWidget);
      expect(_save, findsNothing);
    });

    testWidgets('says it when the rebuilt frame is absent', (tester) async {
      await _recover(
        tester,
        capture: seedCaptureFixture,
        recoverer: IncompleteRecoverer(frameHop: null),
      );

      expect(_incomplete, findsOneWidget);
      expect(_save, findsNothing);
    });

    testWidgets('says it when the hop count is absent', (tester) async {
      // And does not say "backed by only 0 hops", which is what reporting this
      // as the confidence refusal would have put on screen.
      await _recover(
        tester,
        capture: seedCaptureFixture,
        recoverer: IncompleteRecoverer(hopsUsed: null),
      );

      expect(_incomplete, findsOneWidget);
      expect(_lowConfidence, findsNothing);
    });
  });

  testWidgets('an unverified answer is not also blamed on its hop count', (
    tester,
  ) async {
    // Deliberate, and a change: the page used to show the confidence sentence
    // for any shown seed, so a two-hop unverified answer was refused "because"
    // of its hops when the frame being unbuildable is the reason - and the
    // sentence it printed, "it is not offered for transmission", named the
    // wrong cause. The unverified hint is the accurate one, and the hop count
    // is on the capture card above.
    await _recover(
      tester,
      capture: seedCaptureTwoHops,
      recoverer: UnverifiedRecoverer(),
    );

    expect(find.textContaining('The seed is shown for reference'), findsOne);
    expect(_lowConfidence, findsNothing);
    expect(_save, findsNothing);
  });
}
