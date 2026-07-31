import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/dialogs/catalog_compat.dart';
import 'package:qunleashed/pages/asembler/controller.dart';
import 'package:qunleashed/pages/asembler/intro_page.dart';
import 'package:qunleashed/pages/asembler/page.dart';
import 'package:qunleashed/theme/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

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
          compatApi: '86.0',
          onBuildFromSource: () => pressed.add('source'),
          onIgnoreAndContinue: () => pressed.add('ignore'),
          onDecline: () => pressed.add('manager'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compatibility mode - build from source'), findsOneWidget);
    expect(
      find.text('Ignore the warning and continue (API 86.0)'),
      findsOneWidget,
    );
    expect(find.text('Apps manager only'), findsOneWidget);

    await tester.tap(find.text('Compatibility mode - build from source'));
    await tester.tap(find.text('Ignore the warning and continue (API 86.0)'));
    await tester.tap(find.text('Apps manager only'));
    expect(pressed, ['source', 'ignore', 'manager']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('intro page renders and switches SDK channel', (tester) async {
    final controller = AssemblerController.instance;
    controller.setChannel(UfbtUpdateChannel.release);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const AssemblerIntroPage()));
    await tester.pumpAndSettle();

    expect(find.text('Assembler'), findsOneWidget);
    expect(find.text('Build apps from source'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
    expect(find.text('Development'), findsOneWidget);
    expect(find.text('Download SDK'), findsOneWidget);
    expect(find.textContaining('Download toolchain'), findsOneWidget);
    expect(find.text('SDK'), findsOneWidget);
    expect(find.text('Toolchain'), findsOneWidget);

    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    expect(controller.channel, UfbtUpdateChannel.dev);

    controller.setChannel(UfbtUpdateChannel.release);
    expect(tester.takeException(), isNull);
  });

  testWidgets('console page shows logger output and progress', (tester) async {
    final controller = AssemblerController.instance;
    controller.clearLog();

    await tester.pumpWidget(_wrap(const AssemblerConsolePage()));
    await tester.pumpAndSettle();

    expect(find.text('Build console'), findsOneWidget);
    expect(find.text('No output yet'), findsOneWidget);

    controller.logger.info('Deploying SDK for f7');
    controller.logger.build('CC', 'app/hello_world.c');
    controller.logger.raw('Checking for tar..', newline: false);
    controller.logger.raw('yes');
    await tester.pumpAndSettle();

    expect(find.textContaining('[I] Deploying SDK for f7'), findsOneWidget);
    expect(find.text('\tCC\tapp/hello_world.c'), findsOneWidget);
    expect(find.text('Checking for tar..yes'), findsOneWidget);

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
