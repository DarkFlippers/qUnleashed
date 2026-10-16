import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';
import 'package:qunleashed/pages/tools/mifare/recover_controller.dart';
import 'package:qunleashed/pages/tools/mifare/recover_page.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

import 'recover_controller_test.dart'
    show FakeKnownKeys, FakeNested, FakeReaderApi, FakeTagApi, FakeUploadClient;

/// What a progress tick is allowed to cost, and what the saving may not break.
///
/// A hardnested attack emits [RecoverCalculating] up to twice a second for the
/// hours its brute force runs. The page listened to the controller as a whole
/// and answered every one of those with `setState`, which rebuilt every card
/// row already on screen. Sentry QUNLEASHED-H caught that as a hang of at
/// least 2 s on the macOS main thread, sampled inside the poll timer's
/// `onProgress`.
///
/// The page now listens to [RecoverController.entriesChanged] for its rows and
/// puts the readout under a `ListenableBuilder`, so a tick rebuilds the
/// readout and closes over the row instances the last `build` made. That is a
/// saving made by *not rebuilding widgets*, which is the kind that breaks in
/// silence, so these tests pin both directions:
///
/// - a tick leaves the rows alone, and still reaches the readout - a page that
///   had simply stopped updating would pass the first half on its own;
/// - the rows are still rebuilt whenever the page is: a row arrives, the
///   locale changes, the theme changes. Hoisting them out of `build` would
///   pass the first test harder than the correct code does.
void main() {
  // One weak pair, which becomes a row before the hardnested step, then two
  // hardnested groups to park in.
  const log =
      'Sec 1 key A cuid e37aa759 nt0 aaaaaaaa ks0 11111111 par0 1111 '
      'nt1 bbbbbbbb ks1 22222222 par1 1111 dist 0\n'
      'Sec 5 key A cuid e37aa759 nt0 db7df8ae ks0 77ff617e par0 1111\n'
      'Sec 6 key A cuid e37aa759 nt0 aabbccdd ks0 11223344 par0 1111\n';

  // Built once for the suite rather than per pump: three of these tests pump
  // the tree more than once.
  final darkTheme = buildAppTheme(Brightness.dark, const Color(0xFFCC241D));
  final lightTheme = buildAppTheme(Brightness.light, const Color(0xFFCC241D));

  /// The rows. `_EntryRow` is the only widget on this page that uses
  /// [SelectableText], so this cannot quietly start matching the readout.
  final rowFinder = find.byType(SelectableText);
  List<SelectableText> rows(WidgetTester tester) =>
      tester.widgetList<SelectableText>(rowFinder).toList();

  /// Pumps the page under [locale] and [brightness]. Pumping it again with
  /// different ones keeps the page's state, which is what makes a test of
  /// "the rows are rebuilt when the page is" possible.
  Future<void> pumpPage(
    WidgetTester tester, {
    required FakeUploadClient client,
    required RecoverController controller,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.dark,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: brightness == Brightness.dark ? darkTheme : lightTheme,
      home: RecoverPage(client: client, controller: controller),
    ),
  );

  /// Pumps the page and leaves the run parked inside its first hardnested
  /// group, with the weak pair's row on screen.
  ///
  /// The three-step pump is the protocol, not ceremony: one frame to let
  /// `start()` get going, the park to be sure the attack is actually in
  /// flight, and one more to flush the row it produced on the way.
  Future<
    ({
      FakeUploadClient client,
      RecoverController controller,
      _ParkedHardnested hard,
    })
  >
  startParked(WidgetTester tester) async {
    final client = FakeUploadClient(log);
    final hard = _ParkedHardnested();
    final controller = RecoverController(
      client: client,
      mfApi: FakeReaderApi(),
      nestedApi: FakeTagApi(exists: true),
      nestedRecoverer: FakeNested(BigInt.parse('A0A1A2A3A4A5', radix: 16)),
      hardnestedRecoverer: hard,
      knownKeyFilter: (_) => FakeKnownKeys(),
    );
    addTearDown(() {
      if (!hard.release.isCompleted) hard.release.complete();
    });

    await pumpPage(tester, client: client, controller: controller);
    await tester.pump();
    await hard.parked.future;
    await tester.pump();

    expect(
      rowFinder,
      findsNWidgets(1),
      reason: 'the weak pair is the one row that should exist by now',
    );
    return (client: client, controller: controller, hard: hard);
  }

  testWidgets('a tick moves the readout and reuses every row instance', (
    tester,
  ) async {
    final parts = await startParked(tester);
    final before = rows(tester).single;

    parts.hard.report!(0.1);
    await tester.pump();
    expect(
      find.textContaining('10%'),
      findsOneWidget,
      reason: 'the tick has to reach the readout, or this proves nothing',
    );
    expect(rows(tester).single, same(before));

    // A second, different figure: the controller's onProgress drops a repeat,
    // so a test that sent 0.1 twice would show nothing moving and still pass
    // the identity check.
    parts.hard.report!(0.55);
    await tester.pump();
    expect(find.textContaining('55%'), findsOneWidget);
    expect(rows(tester).single, same(before));

    // The other direction: a page that had frozen its rows outright would have
    // passed everything above. The hardnested groups have to arrive.
    parts.hard.release.complete();
    await tester.pumpAndSettle();
    expect(
      rowFinder,
      findsNWidgets(3),
      reason: 'both hardnested groups should have added a row',
    );
  });

  testWidgets('a locale change re-renders the rows already on screen', (
    tester,
  ) async {
    final parts = await startParked(tester);
    final english = rows(tester).single.data;
    expect(english, isNotNull);

    // The same tree and the same page state, only the locale differs. Nothing
    // adds a row, so the rows are whatever the page last built.
    await pumpPage(
      tester,
      client: parts.client,
      controller: parts.controller,
      locale: const Locale('uk'),
    );
    await tester.pump();

    expect(
      rows(tester).single.data,
      isNot(english),
      reason:
          'the rows have to be built by the page build that the locale change '
          'triggers - hoisting them out of build would freeze them here',
    );
  });

  testWidgets('a theme change re-colours the rows already on screen', (
    tester,
  ) async {
    final parts = await startParked(tester);
    final dark = rows(tester).single.style?.color;
    expect(dark, isNotNull);

    await pumpPage(
      tester,
      client: parts.client,
      controller: parts.controller,
      brightness: Brightness.light,
    );
    // Past the lerp, not one frame: MaterialApp animates a theme change, so a
    // single frame still reads the old colour. Not pumpAndSettle either - the
    // readout's progress bar animates for as long as the attack runs, and this
    // one is parked.
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      rows(tester).single.style?.color,
      isNot(dark),
      reason: 'the rows have to be rebuilt by the theme change too',
    );
  });
}

/// Parks inside the attack and hands the test the progress callback, so a tick
/// happens exactly when the test says and not on a timer.
///
/// Near-identical to `FakeParkedHardnested` in recover_controller_test.dart,
/// which the Stop tests use; this one keeps the callback and answers `noKey`.
class _ParkedHardnested implements HardnestedRecoverer {
  final parked = Completer<void>();
  final release = Completer<void>();

  /// The controller's progress handler - what the real recoverer's 500 ms poll
  /// would be calling. There is no poll on this side; that is the point.
  void Function(double fraction)? report;

  @override
  Future<HardnestedResult> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    report = onProgress;
    if (!parked.isCompleted) parked.complete();
    await release.future;
    return (key: null, outcome: HardnestedOutcome.noKey);
  }
}
