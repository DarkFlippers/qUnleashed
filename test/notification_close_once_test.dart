// A notification is taken off the overlay once, however many things ask.
//
// `OverlayEntry.remove` reads the entry's `_overlay` and then nulls it, so a
// second call reads `_overlay!` on an empty field. Debug builds catch that
// with an assertion saying an entry should be removed only once; release
// builds compile it out and raise `TypeError: Null check operator used on a
// null value` instead, reported from whichever caller got there second - with
// the one that got there first nowhere in the trace. QUNLEASHED-S is that
// TypeError, and 0.17.0 still carries the code that produced it.
//
// `OverlayEntry.mounted` was the guard, and it is not that fact: it tracks
// the `_OverlayEntryWidget`, which stays up until the overlay rebuilds. The
// fix is a single idempotent removal keyed on the handle's own field, so what
// these cases have to pin is **two asks and one removal** - not "nothing
// threw", which is also what a test sees when the second ask never happens at
// all. `QNotification.debugCloseRequests` is the ask count; a surviving entry
// would make the removal count two and throw. Hence both assertions, always.
//
// Four of the cases use a degenerate fade-out, and two mechanical details are
// what make it degenerate:
//
//  1. `duration` is under the 16 ms pump, so the auto-close timer fires inside
//     the same `elapse` and before any frame rebuilds the overlay.
//  2. After a single `pump()` the fade-in controller is still at 0.0 -
//     `forward()` runs in that frame's build phase, so its first tick is the
//     *next* frame. `reverse()` from 0.0 therefore has nothing to animate and
//     completes in a microtask, whatever `reverseDuration` says.
//
// So there is no fade-out in those four, rather than a short one, and the
// 150 ms and 110 ms constants in `notification.dart` are not what they rest
// on. Add a second `pump()` before the close and (2) stops holding: the
// controller starts ticking, the overlay rebuilds without the entry first, the
// host and its controller are disposed, the ticker future never completes and
// the callback never runs. The ask count is what notices, which is why it is
// asserted rather than inferred from nothing having thrown.
//
// The tap case is the one that does not need either detail, and it is the
// closest thing here to what a user did: a real fade-out in flight, a close
// arriving in the middle of it, and the callback landing afterwards.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/notification.dart';
import 'package:qunleashed/theme/theme.dart';

/// A lifetime that expires inside the 16 ms pump the window cases use.
///
/// Named rather than written out four times, because the bound *is* the
/// mechanism and nothing at a call site says so. A case given a longer one
/// fails on the ask count with a reason attached, which points at its own
/// argument instead of reading as a production regression.
const _insideThePump = Duration(milliseconds: 1);

/// A lifetime no case here waits out, for the ones not about the window.
const _neverFires = Duration(seconds: 3);

/// Every [OverlayEntry] the framework has reported discarded.
///
/// `OverlayEntry.dispose` is the only thing that releases the entry's
/// `ValueNotifier`, and a missing call is invisible from outside: no
/// exception, no widget left on screen, just a notifier that outlives the
/// notification. So the cases below read the framework's own disposal
/// dispatch - which `dispose` makes through `debugMaybeDispatchDisposed` -
/// rather than asserting that nothing went wrong, which was true while the
/// entry was leaking.
///
/// Available because `kFlutterMemoryAllocationsEnabled` is
/// `bool.fromEnvironment('flutter.memory_allocations') || kDebugMode`, and
/// tests run in debug.
///
/// The objects and not just a count, so a failure can say *which* entry was
/// discarded: the `MaterialApp` under test owns entries of its own, which is
/// also why every assertion is a delta around its own close rather than an
/// absolute.
final _disposedEntries = <OverlayEntry>[];

void _countDisposals(ObjectEvent event) {
  final object = event.object;
  if (event is ObjectDisposed && object is OverlayEntry) {
    _disposedEntries.add(object);
  }
}

/// A themed host for a notification, and a context to show it from.
///
/// Themed because the card reads the app's colour extension, and under a
/// `MaterialApp` because `show` reaches for `Overlay.of(context,
/// rootOverlay: true)`. The context comes from a `Builder` rather than a
/// widget lookup - the shape `archive_failure_toast_test.dart` already uses -
/// because the card contains a `SizedBox` of its own, so a `find.byType`
/// lookup only works for as long as every case resolves its context before
/// showing anything.
Future<BuildContext> pumpHost(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
      home: Scaffold(
        body: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return context;
}

/// A notification on screen, with [firstFrame] naming one case's axis.
///
/// Passing `false` leaves the host unbuilt: no timer, no controller, the entry
/// on the overlay and nothing else in existence yet. That is a page which
/// shows a notice and is disposed in the same frame, and leaving it as an
/// absent `pump()` would hide the one thing that case is about.
///
/// [onTap] is non-null in production - `pages/archive/map/page.dart` passes
/// one - and a null one sends the card's tap handler into a clipboard write
/// instead, which is a different path and not this file's subject.
Future<QNotificationHandle> showProbe(
  WidgetTester tester, {
  required Duration duration,
  bool firstFrame = true,
  VoidCallback? onTap,
}) async {
  final handle = QNotification.show(
    await pumpHost(tester),
    message: 'probe',
    duration: duration,
    onTap: onTap ?? () {},
  );
  if (firstFrame) await tester.pump();
  return handle;
}

void main() {
  setUp(() {
    _disposedEntries.clear();
    FlutterMemoryAllocations.instance.addListener(_countDisposals);
  });

  tearDown(() {
    FlutterMemoryAllocations.instance.removeListener(_countDisposals);
  });

  testWidgets('a holder closing before the auto-close removes it once', (
    tester,
  ) async {
    // The order QUNLEASHED-S arrived in: the holder removes the entry, and
    // the auto-close callback - which has no idea it is second - removes it
    // again. `MapPageState.dispose` is the holder; its stack is not in the
    // report, because the throw lands in the callback.
    final handle = await showProbe(tester, duration: _insideThePump);
    expect(find.text('probe'), findsOneWidget);

    final disposedBefore = _disposedEntries.length;
    handle.close();
    await tester.pump(const Duration(milliseconds: 16));

    expect(QNotification.debugCloseRequests, 2, reason: 'both paths must ask');
    expect(
      _disposedEntries.length - disposedBefore,
      1,
      reason: 'the entry must be discarded, not merely removed',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('and the auto-close finishing before a holder does too', (
    tester,
  ) async {
    // The same pair the other way round, which the old code left reachable
    // for a different reason: its callback removed the entry and left the
    // handle's field set, so the handle stayed armed over an entry already
    // gone. Both timers fire inside one `elapse` with no frame between them.
    final handle = await showProbe(tester, duration: _insideThePump);

    final disposedBefore = _disposedEntries.length;
    Timer(const Duration(milliseconds: 2), handle.close);
    await tester.pump(const Duration(milliseconds: 16));

    expect(QNotification.debugCloseRequests, 2, reason: 'both paths must ask');
    expect(_disposedEntries.length - disposedBefore, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('and a tap and a holder together do too', (tester) async {
    // The third way into `close()`, and the one nothing covered: the card's
    // own tap runs the same `_close` the timer does. Tap first, holder
    // second, both before any frame - the pair that reached a user, with the
    // tap standing in for the timer.
    //
    // A *real* fade-out in flight cannot produce this pair, and it is worth
    // saying so because it is the obvious thing to reach for. Let the fade-in
    // run, tap, then close: the holder's removal marks the overlay dirty, the
    // next frame rebuilds without the entry, the host and its controller are
    // disposed, and `AnimationController.dispose` cancels the ticker future -
    // which never completes rather than rejecting, so `_close` never resumes
    // and the callback never asks at all. One ask, no second removal, nothing
    // to catch. Measured, not reasoned: that version of this case asserted
    // two asks and got one.
    final handle = await showProbe(tester, duration: _neverFires);

    final disposedBefore = _disposedEntries.length;
    await tester.tap(find.text('probe'));
    handle.close();
    await tester.pump(const Duration(milliseconds: 300));

    expect(QNotification.debugCloseRequests, 2, reason: 'both paths must ask');
    expect(_disposedEntries.length - disposedBefore, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('a holder closing before the first frame removes it once', (
    tester,
  ) async {
    // A page that shows a notice and is disposed in the same frame. The host
    // never built, so `entry.mounted` is false - which is the *other* way the
    // old guard was wrong: it skipped the removal entirely and left the
    // notification on screen for good. The duration is the window one for
    // consistency only; with no frame there is no timer to read it.
    final handle = await showProbe(
      tester,
      duration: _insideThePump,
      firstFrame: false,
    );

    final disposedBefore = _disposedEntries.length;
    handle.close();
    await tester.pump();

    expect(QNotification.debugCloseRequests, 1);
    expect(_disposedEntries.length - disposedBefore, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('and closing twice by hand is not a removal twice', (
    tester,
  ) async {
    final handle = await showProbe(tester, duration: _neverFires);

    final disposedBefore = _disposedEntries.length;
    handle.close();
    handle.close();
    await tester.pump(const Duration(milliseconds: 300));

    expect(QNotification.debugCloseRequests, 2);
    // Once, not twice - a second `dispose` asserts, so this pins that the
    // pairing stays behind the same gate as the removal.
    expect(_disposedEntries.length - disposedBefore, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('and a replacement does not strand the one it replaces', (
    tester,
  ) async {
    // `show` closes whatever it is replacing, which is the other caller of
    // the path above - and the only case here that covers it.
    final context = await pumpHost(tester);
    QNotification.show(
      context,
      message: 'first',
      duration: _neverFires,
      onTap: () {},
    );
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    final disposedBefore = _disposedEntries.length;
    QNotification.show(
      context,
      message: 'second',
      duration: _neverFires,
      onTap: () {},
    );
    await tester.pump(const Duration(milliseconds: 300));

    // One ask and one removal, asserted rather than left to "nothing threw" -
    // the header above disclaims that shape, and this case was written with
    // it.
    expect(QNotification.debugCloseRequests, 1);
    expect(_disposedEntries.length - disposedBefore, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });
}
