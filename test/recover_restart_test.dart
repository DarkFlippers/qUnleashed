import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/recover_controller.dart';
import 'package:qunleashed/pages/tools/mifare/recover_models.dart';
import 'package:qunleashed/pages/tools/mifare/recover_page.dart';
import 'package:qunleashed/theme/theme.dart';

import 'recover_controller_test.dart'
    show
        FakeInterruptingHardnested,
        FakeKnownKeys,
        FakeNested,
        FakeReaderApi,
        FakeTagApi,
        FakeUploadClient;

/// Running again after a Stop.
///
/// A stopped run lands in `RecoverSaved(stopped: true)` - the same terminal
/// state a *finished* run uses - and that branch rendered a summary, a footnote
/// and nothing to press. So the only way to start over was to leave the page
/// and come back, because that is what builds a fresh controller and starts it.
/// Nobody would guess that, and the keys already found are on screen while it
/// is the one thing you cannot act on.
///
/// Restart, not resume: the engine keeps no checkpoint, so continuing where it
/// left off is not something that can be offered.
void main() {
  // One weak pair recovered before the hardnested step, then two hardnested
  // groups - so there is something to keep and a step left to skip.
  const log =
      'Sec 1 key A cuid e37aa759 nt0 aaaaaaaa ks0 11111111 par0 1111 '
      'nt1 bbbbbbbb ks1 22222222 par1 1111 dist 0\n'
      'Sec 5 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111\n'
      'Sec 6 key A cuid e37aa759 nt0 aabbccdd ks0 11223344 par0 1111\n';

  testWidgets('a stopped run can be started again from the page', (
    tester,
  ) async {
    final client = FakeUploadClient(log);
    late final RecoverController controller;
    // Stops the run from inside the first attack, which is the only moment
    // `canStop` is true - the same way the controller's own Stop tests reach
    // this state.
    var stopNext = true;
    final hard = FakeInterruptingHardnested(
      onStarted: () {
        if (!stopNext) return;
        stopNext = false;
        controller.stop();
      },
    );
    controller = RecoverController(
      client: client,
      mfApi: FakeReaderApi(),
      nestedApi: FakeTagApi(exists: true),
      nestedRecoverer: FakeNested(BigInt.parse('A0A1A2A3A4A5', radix: 16)),
      hardnestedRecoverer: hard,
      knownKeyFilter: (_) => FakeKnownKeys(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
        home: RecoverPage(
          client: client,
          // The page owns and disposes what this returns; it only decides what
          // is built, so the native recoverers stay out of the test.
          createController: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      (controller.state as RecoverSaved).stopped,
      isTrue,
      reason: 'the case has to actually be a stopped run',
    );
    expect(
      hard.calls,
      1,
      reason: 'and the Stop has to have skipped the second group',
    );

    final again = find.byType(FilledButton);
    expect(
      again,
      findsOneWidget,
      reason: 'a stopped run has to offer a way to run it again',
    );

    await tester.tap(again);
    await tester.pumpAndSettle();

    // The second run is the assertion: the button is wired to something that
    // starts one, not merely present. Two more attacks because this run is not
    // interrupted - which also pins that a Stop does not latch into the next
    // run.
    expect(
      hard.calls,
      3,
      reason: 'pressing it runs both hardnested groups this time',
    );
  });
}
