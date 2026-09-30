import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/overview/failure_toast.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

/// The two ways the archive puts a reason in front of the user, and why they
/// are not one.
///
/// [reportArchiveFailure] takes the reason as the signal: these operations
/// return void, so a null reason is how the page knows nothing went wrong.
/// [withArchiveReason] is for the ones that return a bool and already know -
/// there the same null must not swallow the message. Collapsing the two
/// silently drops "Failed to launch X" for every failure that has no reason
/// attached, which is what a disconnected Flipper is.
Future<BuildContext> pump(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      // The notification card reads the app's colour extension, so a bare
      // MaterialApp renders it as a null check on a missing theme.
      theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );
  return ctx;
}

void main() {
  group('a message that already knows it failed', () {
    testWidgets('carries the reason when there is one', (tester) async {
      final ctx = await pump(tester);

      expect(
        withArchiveReason(ctx, 'Failed to launch Clock', 'ERROR_BUSY'),
        contains('ERROR_BUSY'),
      );
    });

    // The regression this exists for: a Flipper that is not connected fails
    // the launch without a reason, and the user still has to be told.
    testWidgets('is still shown when there is not', (tester) async {
      final ctx = await pump(tester);

      expect(
        withArchiveReason(ctx, 'Failed to launch Clock', null),
        'Failed to launch Clock',
      );
    });

    testWidgets('treats an empty reason as no reason', (tester) async {
      final ctx = await pump(tester);

      expect(
        withArchiveReason(ctx, 'Failed to launch Clock', ''),
        'Failed to launch Clock',
      );
    });

    testWidgets('keeps the message ahead of the reason', (tester) async {
      final ctx = await pump(tester);

      final joined = withArchiveReason(ctx, 'Rename failed', 'ERROR_DENIED');

      expect(
        joined.indexOf('Rename failed'),
        lessThan(joined.indexOf('ERROR_DENIED')),
      );
    });
  });

  group('a message whose reason is the signal', () {
    testWidgets('says nothing at all when nothing failed', (tester) async {
      final ctx = await pump(tester);

      reportArchiveFailure(ctx, null, 'Delete failed');
      await tester.pump();

      expect(find.text('Delete failed'), findsNothing);
    });

    testWidgets('shows the message and the reason together', (tester) async {
      final ctx = await pump(tester);

      reportArchiveFailure(ctx, 'ERROR_STORAGE_DENIED', 'Delete failed');
      await tester.pump();

      expect(find.textContaining('ERROR_STORAGE_DENIED'), findsOneWidget);
      expect(find.textContaining('Delete failed'), findsOneWidget);
    });
  });
}
