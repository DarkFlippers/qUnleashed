import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/components/dialogs/catalog_compat.dart';
import 'package:qunleashed/pages/asembler/controller.dart';
import 'package:qunleashed/pages/asembler/page.dart';
import 'package:qunleashed/pages/asembler/settings_page.dart';
import 'package:qunleashed/pages/asembler/widgets/progress_panel.dart';
import 'package:qunleashed/theme/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

void _expectOneOf(List<String> labels) {
  final shown = labels
      .where((label) => find.text(label).evaluate().isNotEmpty)
      .toList();
  expect(shown, hasLength(1), reason: 'expected one of $labels, got $shown');
}

void main() {
  testWidgets('compat dialog offers three ways to proceed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final pressed = <String>[];
    await tester.pumpWidget(
      _wrap(
        CatalogCompatDialog(
          deviceApi: '88.2',
          serverApi: '86.0',
          onBuildFromSource: () => pressed.add('source'),
          onIgnoreAndContinue: () => pressed.add('ignore'),
          onDecline: () => pressed.add('manager'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compatibility mode'), findsOneWidget);
    expect(
      find.text('Builds apps from source for your firmware.'),
      findsOneWidget,
    );
    expect(find.text('Ignore warning'), findsOneWidget);
    expect(find.text('Apps manager only'), findsOneWidget);

    await tester.tap(find.text('Compatibility mode'));
    await tester.tap(find.text('Ignore warning'));
    await tester.tap(find.text('Apps manager only'));
    expect(pressed, ['source', 'ignore', 'manager']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compat dialog drops the ignore option when asked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        CatalogCompatDialog(
          deviceApi: '90.0',
          serverApi: '86.0',
          onBuildFromSource: () {},
          onIgnoreAndContinue: null,
          onDecline: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compatibility mode'), findsOneWidget);
    expect(find.text('Ignore warning'), findsNothing);
    expect(find.text('Apps manager only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compat dialog drops source builds off desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        CatalogCompatDialog(
          deviceApi: '88.2',
          serverApi: '86.0',
          onBuildFromSource: null,
          onIgnoreAndContinue: () {},
          onDecline: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compatibility mode'), findsNothing);
    expect(find.textContaining('desktop'), findsNothing);
    expect(find.text('Ignore warning'), findsOneWidget);
    expect(find.text('Apps manager only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings page renders and switches SDK channel', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    controller.setChannel(UfbtUpdateChannel.release);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const AssemblerSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Assembler settings'), findsOneWidget);
    expect(find.text('Flibler (Flipper Assembler Tool)'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
    expect(find.text('Development'), findsOneWidget);
    expect(find.text('Unleashed'), findsOneWidget);
    expect(find.text('Official'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text(kUnleashedIndexUrl), findsOneWidget);
    expect(find.text(kOfficialIndexUrl), findsOneWidget);
    // The labels follow the local ufbt state, so only one of each set shows.
    _expectOneOf(const ['Download SDK', 'Update SDK', 'Downloading SDK…']);
    _expectOneOf(const [
      'Download toolchain',
      'Update toolchain',
      'Toolchain ready',
      'Downloading toolchain…',
    ]);
    expect(find.text('SDK'), findsOneWidget);
    expect(find.text('Toolchain'), findsOneWidget);
    expect(find.byType(AssemblerProgressPanel), findsNothing);

    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    expect(controller.channel, UfbtUpdateChannel.dev);

    controller.setChannel(UfbtUpdateChannel.release);
    expect(tester.takeException(), isNull);
  });

  test(
    'toolchain check reports its outcome when nothing is downloaded',
    () async {
      final controller = AssemblerController.instance;
      if (!AssemblerController.isSupported ||
          !controller.installer.status().toolchain.isUpToDate) {
        markTestSkipped('toolchain is not deployed');
        return;
      }
      controller.clearLog();

      expect(await controller.downloadToolchain(), isTrue);

      final log = controller.logAsText();
      expect(log, contains('Checking toolchain'));
      expect(log, contains('is up to date'));
      controller.clearLog();
    },
  );

  test('logger is mirrored into the dart console', () async {
    final controller = AssemblerController.instance;
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);

    controller.clearLog();
    controller.logger.info('Deploying SDK for f7');
    controller.logger.build('CC', 'app/hello_world.c');
    final task = controller.logger.progress('Downloading:', total: 100);
    task.finish();
    controller.clearLog();

    expect(printed.any((l) => l.endsWith('[I] Deploying SDK for f7')), isTrue);
    expect(printed, contains('\tCC\tapp/hello_world.c'));
    expect(printed, contains('Downloading:'));
    expect(printed.any((l) => l.contains('100.0%')), isTrue);
  });

  testWidgets('console page shows logger output and progress', (tester) async {
    final controller = AssemblerController.instance;
    controller.clearLog();

    await tester.pumpWidget(_wrap(const AssemblerConsolePage()));
    await tester.pumpAndSettle();

    expect(find.text('Assembler'), findsOneWidget);
    expect(find.text('No output yet'), findsOneWidget);

    controller.logger.info('Deploying SDK for f7');
    controller.logger.build('CC', 'app/hello_world.c');
    controller.logger.raw('Checking for tar..', newline: false);
    controller.logger.raw('yes');
    await tester.pumpAndSettle();

    expect(find.textContaining('[I] Deploying SDK for f7'), findsOneWidget);
    expect(
      find.text('\tCC\tapp/hello_world.c', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Checking for tar..yes'), findsOneWidget);

    // Only the build tag is coloured, the value follows the theme.
    final buildLine = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('\tCC\t'),
      ),
    );
    final spans = <TextSpan>[];
    buildLine.text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').isNotEmpty) spans.add(span);
      return true;
    });
    expect(spans[0].text, '\tCC');
    expect(spans[0].style?.color, const Color(0xFFCC241D));
    expect(spans[1].text, '\tapp/hello_world.c');
    expect(spans[1].style?.color, isNull);

    final task = controller.logger.progress(
      'Downloading toolchain:',
      total: 1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Downloading toolchain:'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    task.update(current: 400);
    await tester.pumpAndSettle();
    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text('400 B / 1000 B'), findsOneWidget);

    task.finish();
    await tester.pumpAndSettle();
    controller.clearLog();
    expect(tester.takeException(), isNull);
  });
}
