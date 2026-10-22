// Who words a cancelled transfer, and whether anyone is left to hear it.
//
// `openRemoteFileInEditor` takes a `cancelledMessage` callback, and the only
// caller that passes one passes a State method - `_FileManagerPageState.
// _cancelledMessage`, which reads `context.l10n` to word itself. The catch
// asked it for the wording first and checked `context.mounted` second, so a
// download cancelled after the user left the page read `State.context` on a
// disposed State. The open was abandoned where `guarded` caught it: no
// notification, and the refresh behind it never ran. QUNLEASHED-1F.
//
// Both halves are here. The disposed case must not ask; the mounted case must
// still ask and still show, because a guard that never lets go is the same
// green as a guard that works.
import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/notification.dart';
import 'package:qunleashed/pages/archive/editor/open.dart';
import 'package:qunleashed/theme/theme.dart';

/// Themed, because the toast reads `appColors` off a theme extension that a
/// bare [MaterialApp] does not carry.
Widget wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

/// A page to open a file from, and to dispose while the open is in flight.
///
/// Its [cancelledMessage] stands in for the file manager's: what matters is
/// that the wording is read off *this State's* `context`, because the
/// `State.context` getter is the crash - it asserts "This widget has been
/// unmounted" in debug and dereferences a null `_element` in release. Which
/// inherited widget is looked up past it is irrelevant; `MediaQuery` only
/// keeps the stand-in off the app's `Localizations` wiring.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  /// Whether [cancelledMessage] ran at all, which is what the guard is about -
  /// a null return cannot tell "never asked" from "asked, said nothing".
  bool asked = false;

  /// What [cancelledMessage] answers. Null is the real one's unacknowledged
  /// cancel: the transfer leaves the screen, but nothing claims it stopped.
  String? reply = 'cancelled';

  String? cancelledMessage(FlipperCancelledException e) {
    // Set before the context read, so it still records that the callback ran
    // on the path where that read throws.
    asked = true;
    MediaQuery.maybeOf(context);
    return reply;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  /// Starts an open against [state]'s context and hands back its future.
  Future<bool> openAgainst(_HostState state, Completer<String?> download) =>
      openRemoteFileInEditor(
        state.context,
        remotePath: '/ext/badge.nfc',
        download: () => download.future,
        upload: (_) async => false,
        cancelledMessage: state.cancelledMessage,
      );

  testWidgets('a cancel that lands after dispose is not worded', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    final download = Completer<String?>();

    final opened = openAgainst(state, download);

    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    // `mounted` rather than nothing: it pins that the element reached
    // `unmount` rather than only `deactivate`, which is the state that makes
    // `context.mounted` false and `State.context` throw.
    expect(state.mounted, isFalse, reason: 'the page the user left');
    // No pump between this and the await below: the error is delivered to a
    // listener attached in the same synchronous run, and a pump in between
    // would leave it momentarily unhandled.
    download.completeError(FlipperReadCancelledException('/ext/badge.nfc'));

    expect(await opened, isFalse, reason: 'nothing was opened');
    expect(
      state.asked,
      isFalse,
      reason: 'there is no screen left to say it on',
    );
  });

  testWidgets('a cancel on a page still there is worded, and shown', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    final download = Completer<String?>();

    final opened = openAgainst(state, download);
    download.completeError(FlipperReadCancelledException('/ext/badge.nfc'));

    expect(await opened, isFalse);
    // Pumped rather than settled: the toast dismisses itself, and settling
    // runs past its whole lifetime and finds nothing.
    await tester.pump();
    await tester.pump();

    expect(state.asked, isTrue, reason: 'the guard lets a live page through');
    expect(
      find.text('cancelled'),
      findsOneWidget,
      reason: 'and the wording it gave back reaches the screen',
    );
  });

  // The other half of the real callback's contract: it returns null when the
  // firmware never acknowledged the cancel, and then nothing is claimed.
  testWidgets('a cancel it declines to word shows nothing', (tester) async {
    await tester.pumpWidget(wrap(const _Host()));
    final state = tester.state<_HostState>(find.byType(_Host))..reply = null;
    final download = Completer<String?>();

    final opened = openAgainst(state, download);
    download.completeError(FlipperReadCancelledException('/ext/badge.nfc'));

    expect(await opened, isFalse);
    await tester.pump();
    await tester.pump();

    expect(state.asked, isTrue, reason: 'asked, and said nothing');
    expect(find.byType(QNotification), findsNothing);
  });
}
