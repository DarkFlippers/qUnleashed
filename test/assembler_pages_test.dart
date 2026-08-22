import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/services/assembler/controller.dart';
import 'package:qunleashed/pages/flibler/page.dart';
import 'package:qunleashed/services/assembler/remote_build_service.dart';
import 'package:qunleashed/pages/option/pages/flibler.dart';
import 'package:qunleashed/pages/tools/overview/page.dart';
import 'package:qunleashed/pages/flibler/widgets/progress_panel.dart';
import 'package:qunleashed/theme/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: child,
);

/// The widget binding replaces HttpClient with a stub that answers 400, so the
/// page gets its status from a fake service; the real one is covered by a
/// socket test in remote_build_test.dart.
class _StubRemote extends RemoteBuildService {
  _StubRemote() : super.test(serverUrl: 'https://build.test', sharedKey: 'k');

  @override
  Future<RemoteServerStatus> serverStatus() async => const RemoteServerStatus(
    version: '9.9.9',
    queueLength: 2,
    sdkVersions: ['unlshd-090 · f7'],
  );
}

void _expectOneOf(List<String> labels) {
  final shown = labels
      .where((label) => find.text(label).evaluate().isNotEmpty)
      .toList();
  expect(shown, hasLength(1), reason: 'expected one of $labels, got $shown');
}

void main() {
  testWidgets('settings page renders and switches SDK channel', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    controller.setChannel(UfbtUpdateChannel.release);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const AssemblerSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Assembler settings'), findsOneWidget);
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
      'Reinstall toolchain',
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

  testWidgets('settings page offers a build backend choice', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    addTearDown(() => controller.setPreference(AssemblerBackendPreference.auto));
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(AssemblerSettingsPage(remote: _StubRemote())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build with'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Build server'), findsOneWidget);
    expect(controller.preference, AssemblerBackendPreference.auto);

    // Pinning the server is the only sticky choice; the local controls stay
    // where they are, because that is where the SDK is downloaded.
    await tester.tap(find.text('Build server'));
    await tester.pumpAndSettle();
    expect(controller.preference, AssemblerBackendPreference.server);
    expect(controller.backend, AssemblerBackend.server);
    expect(controller.usesServerBuild, isTrue);
    expect(
      find.text('SDK channel'),
      AssemblerController.isSupported ? findsOneWidget : findsNothing,
    );
    expect(find.text('Online · v9.9.9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server backend shows live server status', (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'assembler_backend': 'server',
    });
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    addTearDown(() => controller.setPreference(AssemblerBackendPreference.auto));
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(AssemblerSettingsPage(remote: _StubRemote())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Online · v9.9.9'), findsOneWidget);
    expect(find.text('unlshd-090 · f7'), findsOneWidget);
    expect(find.text('2 in line'), findsOneWidget);
    expect(find.text('Check server'), findsOneWidget);
    expect(
      find.textContaining('Now: build server'),
      findsOneWidget,
      reason: 'the page says where the next build goes',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Flibler tool follows the local toolchain', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    addTearDown(() => controller.setPreference(AssemblerBackendPreference.auto));
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const ToolsPage()));
    await tester.pumpAndSettle();

    // Building a folder or a repo needs a deployed SDK and toolchain here.
    expect(
      find.text('Flibler'),
      controller.localReady ? findsOneWidget : findsNothing,
    );

    // Nothing is compiled on this computer once the server is in charge.
    await controller.setPreference(AssemblerBackendPreference.server);
    await tester.pumpAndSettle();
    expect(find.text('Flibler'), findsNothing);

    await controller.setPreference(AssemblerBackendPreference.auto);
    await tester.pumpAndSettle();
    expect(
      find.text('Flibler'),
      controller.localReady ? findsOneWidget : findsNothing,
    );
  });

  test('a stored server choice survives a reload, nothing else does', () async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;

    await controller.loadSettings();
    expect(controller.preference, AssemblerBackendPreference.auto);
    // Automatic follows the local ufbt state instead of the platform.
    expect(
      controller.backend,
      controller.localReady ? AssemblerBackend.local : AssemblerBackend.server,
    );

    await controller.setPreference(AssemblerBackendPreference.server);
    await controller.loadSettings();
    expect(controller.preference, AssemblerBackendPreference.server);
    expect(controller.usesServerBuild, isTrue);

    // The backend older builds stored as "local" means "automatic" now.
    SharedPreferences.setMockInitialValues(const {
      'assembler_backend': 'local',
    });
    await controller.loadSettings();
    expect(controller.preference, AssemblerBackendPreference.auto);

    await controller.setPreference(AssemblerBackendPreference.auto);
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
