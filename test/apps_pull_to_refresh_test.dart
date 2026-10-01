import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a pull-to-refresh handler has to return.
///
/// `RefreshIndicator` holds its spinner until the future `onRefresh` gives back
/// settles. All three apps tables handed it `() async => unawaited(work())`,
/// which settles at once - so the spinner appeared and vanished in the same
/// frame while the download or the device scan had not begun, and the user's
/// answer to that is to pull again. #23.
///
/// The handler also has to not reject, which is the other half of why these
/// sites use `guarded` rather than awaiting the work directly. A rejected
/// `onRefresh` is not caught by the indicator and does not reach
/// `FlutterError.onError` either: it becomes an uncaught *zone* error, which in
/// the app is #89's `[uncaught]` with no operation on it, and which this
/// harness reports as a failure of whichever case is running. That is why it is
/// written here rather than asserted - capturing a zone error inside
/// `testWidgets` means fighting the binding for the zone.
///
/// The indicator rather than `AppsTable`, deliberately. `AppsTable`'s column
/// header overflows its row by 8.2 pixels at every surface width, which is a
/// rendering error and fails any case that builds it - a separate bug, found
/// while writing this and not fixed here. What is left to cover is the shape of
/// the handler, which is what #23 got wrong; the three call sites themselves
/// are held by `test/unawaited_budget_test.dart`, since going back to
/// `unawaited` there raises its number.
void main() {
  late Completer<void> work;
  late int started;

  setUp(() {
    work = Completer<void>();
    started = 0;
  });

  Widget wrap(Future<void> Function() onRefresh) => MaterialApp(
    home: Scaffold(
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          children: const [
            SizedBox(height: 400, child: Text('one')),
            SizedBox(height: 400, child: Text('two')),
          ],
        ),
      ),
    ),
  );

  /// Drags far enough to arm the indicator, then lets the drag settle and the
  /// indicator reach its armed frame.
  Future<void> pull(WidgetTester tester) async {
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  bool spinning() =>
      find.byType(RefreshProgressIndicator).evaluate().isNotEmpty;

  /// Lets the completed handler be seen, without waiting on the indicator.
  ///
  /// `pumpAndSettle` cannot be used once the spinner is up: a refreshing
  /// `RefreshProgressIndicator` animates indefinitely, so there is never a
  /// frame with nothing scheduled. Nothing below asserts on the dismiss
  /// animation either - how many frames it takes to go is Flutter's business,
  /// and the contract under test is which future the handler returns.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('keeps the spinner until the work is done', (tester) async {
    await tester.pumpWidget(
      wrap(() {
        started += 1;
        return work.future;
      }),
    );

    await pull(tester);

    expect(started, 1, reason: 'the handler ran');
    expect(spinning(), isTrue, reason: 'and the spinner is waiting for it');

    work.complete();
    await drain(tester);
  });

  // The shape this replaced, kept as a case rather than a sentence: it is the
  // whole of the bug and it is one `unawaited` away from coming back.
  testWidgets('a handler that only starts the work does not', (tester) async {
    await tester.pumpWidget(
      wrap(() async {
        started += 1;
        unawaited(work.future);
      }),
    );

    await pull(tester);
    await tester.pumpAndSettle();

    expect(started, 1, reason: 'it did run');
    expect(
      spinning(),
      isFalse,
      reason: 'and settled at once, which is what made the spinner flash',
    );

    work.complete();
  });
}
