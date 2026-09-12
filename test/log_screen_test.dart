import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/option/pages/logs.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/theme/theme.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

/// Silences the console while a test records something, so the run stays
/// readable. Restored inline; flutter_test rejects addTearDown for this.
void quietly(void Function() body) {
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  try {
    body();
  } finally {
    debugPrint = previous;
  }
}

void main() {
  setUp(LogService.clearHistory);
  tearDown(LogService.clearHistory);

  // The half that makes the other half worth anything. Errors survive a
  // release build now, but a buffer nobody can open is the same as no buffer.
  testWidgets('the screen shows what was recorded', (tester) async {
    quietly(() => LogService.error('[CLI] write failed: no transport'));

    await tester.pumpWidget(wrap(const LogSettingsPage()));
    await tester.pump();

    expect(
      find.textContaining('write failed: no transport', findRichText: true),
      findsOneWidget,
    );
  });

  // An empty log means nothing went wrong, not that recording is off. Saying
  // nothing at all would leave the user unable to tell those apart.
  testWidgets('an empty log says so rather than showing a blank page', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LogSettingsPage()));
    await tester.pump();

    expect(find.text(l10nGlobal.logEmpty), findsOneWidget);
  });

  // Copying is the one thing anyone comes here to do: the app has no crash
  // reporting, so this is the whole route from "it failed" to a bug report.
  testWidgets('copying puts every entry on the clipboard', (tester) async {
    quietly(() {
      LogService.error('first failure');
      LogService.error('second failure');
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
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

    await tester.pumpWidget(wrap(const LogSettingsPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.copy_all_outlined));
    await tester.pump();

    expect(copied, contains('first failure'));
    expect(copied, contains('second failure'));
  });

  testWidgets('clearing empties the log and the screen with it', (
    tester,
  ) async {
    quietly(() => LogService.error('something to forget'));

    await tester.pumpWidget(wrap(const LogSettingsPage()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(LogService.history, isEmpty);
    expect(find.text(l10nGlobal.logEmpty), findsOneWidget);
  });

  // A snapshot on purpose - lines must not move under someone reading a
  // failure - so there has to be a way to ask for the newer ones.
  testWidgets('refreshing picks up what arrived since the page opened', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LogSettingsPage()));
    await tester.pump();

    quietly(() => LogService.error('arrived while the page was open'));
    expect(
      find.textContaining('arrived while', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(
      find.textContaining('arrived while', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('copy and clear are offered only when there is something to', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LogSettingsPage()));
    await tester.pump();

    for (final icon in [Icons.copy_all_outlined, Icons.delete_outline]) {
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
            .onPressed,
        isNull,
        reason: '$icon does nothing on an empty log',
      );
    }
  });
}
