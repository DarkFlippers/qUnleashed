// `copyTextToClipboard`, and the branch that reports a refusal.
//
// This had one test and it was not here: it drove the helper through the Log
// screen's Copy button, in `log_screen_test.dart` and then
// `diagnostics_screen_test.dart`. ADR 0013 §1 removed that button, and the
// test went with the screen - which left the helper's whole reason for
// existing uncovered while six call sites still used it.
//
// The helper's own doc says what that reason is: the five hand-written
// copy-then-confirm blocks it replaced awaited the write inside a discarded
// future, so a `PlatformException` became an unhandled async error and the
// only signal was a toast that never appeared. Android caps a clipboard write
// near a megabyte over its Binder transaction, so the throw is real and
// arrives exactly when the payload is biggest.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/clipboard.dart';
import 'package:qunleashed/components/notification.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

/// A button that copies, so the helper runs with a real `BuildContext`.
///
/// `showNotification` reaches for `Overlay.of(context, rootOverlay: true)`, so
/// the helper cannot be called against a bare context - it needs to be under a
/// `MaterialApp`, and the tap is the least ceremonious way to get there.
Widget wrap(String text) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => copyTextToClipboard(context, text),
          child: const Text('copy'),
        ),
      ),
    ),
  ),
);

/// Answers `Clipboard.setData` with [refuse], or records what went through.
///
/// Returns the holder for the copied text so the success case can read it.
List<String> mockClipboard(WidgetTester tester, {Object? refuse}) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        if (refuse != null) throw refuse;
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('a refused clipboard says so instead of going quiet', (
    tester,
  ) async {
    // The branch the helper exists for. `TransactionTooLargeException` is the
    // code Android raises when the text is over the Binder cap.
    mockClipboard(
      tester,
      refuse: PlatformException(code: 'TransactionTooLargeException'),
    );

    await tester.pumpWidget(wrap('a payload too big to carry'));
    await tester.tap(find.text('copy'));
    // Pumped rather than settled: the toast dismisses itself, and settling
    // runs past its whole lifetime and finds nothing.
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('TransactionTooLargeException'),
      findsOneWidget,
      reason: 'the failure names itself, rather than showing no toast at all',
    );
    expect(
      find.text(l10nGlobal.commonCopied),
      findsNothing,
      reason: 'and does not claim success',
    );
  });

  testWidgets('a write that lands confirms it, and carries the text', (
    tester,
  ) async {
    final copied = mockClipboard(tester);

    await tester.pumpWidget(wrap('0.16.0-dev · 108170 · abc1234'));
    await tester.tap(find.text('copy'));
    await tester.pump();
    await tester.pump();

    expect(copied.single, '0.16.0-dev · 108170 · abc1234');
    expect(find.text(l10nGlobal.commonCopied), findsOneWidget);
  });

  testWidgets('a caller-supplied message replaces the default', (tester) async {
    // Four of the six call sites pass one. A helper that ignored it would pass
    // every other test in this file.
    mockClipboard(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => copyTextToClipboard(
                  context,
                  'x',
                  message: 'Seed copied',
                  type: QNotificationType.good,
                ),
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('copy'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Seed copied'), findsOneWidget);
    expect(find.text(l10nGlobal.commonCopied), findsNothing);
  });
}
