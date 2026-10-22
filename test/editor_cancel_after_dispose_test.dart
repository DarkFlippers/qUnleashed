import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/editor/open.dart';

/// A download cancelled after the page that started it has gone.
///
/// `openRemoteFileInEditor` asked its caller to word the cancel first and
/// checked `context.mounted` second. The wording comes from a State - the file
/// manager's `_cancelledMessage` reads `context.l10n` - and reading
/// `State.context` after dispose is a null check on a null `_element`. In a
/// test that is an assert; in the release build the user is running it is a
/// TypeError that escapes as an unhandled error. Walking away from a download
/// is precisely how a cancel arrives late. QUNLEASHED-1F.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  /// Whether [cancelledMessage] ran at all, which is what the fix is about -
  /// a null return cannot tell "never asked" from "asked, said nothing".
  bool asked = false;

  String? cancelledMessage(FlipperCancelledException e) {
    asked = true;
    // The shape the real one has: the wording is looked up off the State's own
    // context. This is the read that threw.
    return MediaQuery.maybeOf(context) == null ? null : 'cancelled';
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('a cancel that lands after dispose is not worded', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    final state = tester.state<_HostState>(find.byType(_Host));
    final download = Completer<String?>();

    final opened = openRemoteFileInEditor(
      state.context,
      remotePath: '/ext/badge.nfc',
      download: () => download.future,
      upload: (_) async => false,
      cancelledMessage: state.cancelledMessage,
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(state.mounted, isFalse, reason: 'the page the user left');
    download.completeError(FlipperReadCancelledException('/ext/badge.nfc'));

    expect(
      await opened,
      isFalse,
      reason: 'nothing was opened, and nothing threw on the way there',
    );
    expect(
      state.asked,
      isFalse,
      reason: 'there is no screen left to say it on',
    );
  });
}
