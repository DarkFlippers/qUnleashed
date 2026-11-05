// What a cancelled download tells the user, and what it does when there is
// nobody left to tell.
//
// `openRemoteFileInEditor` used to take the wording as a callback, and the
// only caller passed a State method that read `context.l10n`. A cancel that
// landed after the user left the page therefore read `State.context` on a
// disposed State, and `guarded` swallowed the throw along with the whole
// open - no notification, and the refresh behind it never ran. QUNLEASHED-1F.
//
// It now takes `cancelAcknowledged`, a predicate off the controller, and words
// the constant here from the context-free `l10n`. These cases pin both ends of
// that: what is said while the page is there, and that the vanished page costs
// nothing but the toast.
import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/notification.dart';
import 'package:qunleashed/pages/archive/editor/open.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

/// Themed, because the toast reads `appColors` off a theme extension that a
/// bare [MaterialApp] does not carry.
Widget wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

/// A page to open a file from, and to dispose while the open is in flight.
///
/// It exists for its [State], whose `context` is the one the cancel used to be
/// worded off after it had died.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  /// Starts an open against [state]'s context and hands back its future.
  Future<bool> openAgainst(
    _HostState state,
    Completer<String?> download, {
    bool acknowledged = true,
  }) => openRemoteFileInEditor(
    state.context,
    remotePath: '/ext/badge.nfc',
    download: () => download.future,
    upload: (_) async => false,
    cancelAcknowledged: (_) => acknowledged,
  );

  testWidgets('an acknowledged cancel says so', (tester) async {
    await tester.pumpWidget(wrap(const _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    final download = Completer<String?>();

    final opened = openAgainst(state, download);
    download.completeError(FlipperReadCancelledException('/ext/badge.nfc'));

    expect(await opened, isFalse, reason: 'nothing was opened');
    // Pumped rather than settled: the toast dismisses itself, and settling
    // runs past its whole lifetime and finds nothing.
    await tester.pump();
    await tester.pump();

    expect(find.text(l10nGlobal.fmTransferCancelled), findsOneWidget);
  });

  // The other half of the predicate: the transfer leaves the screen, but
  // nothing claims it stopped.
  testWidgets('a cancel the firmware never acknowledged says nothing', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    final download = Completer<String?>();

    final opened = openAgainst(state, download, acknowledged: false);
    download.completeError(FlipperReadCancelledException('/ext/badge.nfc'));

    expect(await opened, isFalse);
    await tester.pump();
    await tester.pump();

    expect(find.byType(QNotification), findsNothing);
  });

  // The reported bug. Before `cancelAcknowledged`, the wording was read off
  // this State and this threw instead of returning.
  testWidgets('a cancel that lands after the page has gone is survivable', (
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

    expect(
      await opened,
      isFalse,
      reason: 'it returns rather than throwing on the dead context',
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(QNotification),
      findsNothing,
      reason: 'there is no screen left to say it on',
    );
  });
}
