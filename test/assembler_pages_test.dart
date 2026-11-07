import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/services/assembler/controller.dart';
import 'package:qunleashed/pages/flibler/page.dart';
import 'package:qunleashed/services/assembler/remote_build_service.dart';
import 'package:qunleashed/pages/option/pages/apps.dart';
import 'package:qunleashed/pages/tools/overview/page.dart';
import 'package:qunleashed/pages/flibler/widgets/progress_panel.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

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

const _fliblerSubtitle = 'Build an app from a folder or repo';
const _fliblerNeedsSdk = 'Needs the SDK deployed in the settings';

/// A ufbt state this test owns, so the Flibler cases do not depend on whatever
/// is in the machine's own ~/.ufbt - which is neither deterministic nor the
/// thing being tested.
UfbtStatus _ufbtStatus({required bool ready}) => UfbtStatus(
  stateDir: '',
  downloadDir: '',
  toolchainDir: '',
  sdkDir: '',
  previousTask: ready ? SdkDeployTask(hwTarget: 'f7') : null,
  toolchain: UfbtToolchainInfo(
    archDir: '',
    version: 'v1',
    url: '',
    installedVersion: ready ? 'v1' : null,
    isDeployed: ready,
  ),
);

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

/// The apps settings page also asks the catalog, whose request times out
/// after 15 s; fake time is moved past it so no timer outlives the test.
Future<void> _drainCatalog(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 16));

Future<void> _tapRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// The download actions are icon buttons named by their tooltip, which is
/// the action followed by its details, such as the size.
void _expectOneAction(List<String> labels) {
  final shown = labels
      .where(
        (label) => find
            .byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  (w.tooltip == label ||
                      (w.tooltip?.startsWith('$label · ') ?? false)),
            )
            .evaluate()
            .isNotEmpty,
      )
      .toList();
  expect(shown, hasLength(1), reason: 'expected one of $labels, got $shown');
}

/// A settings page at a desktop window, settled.
///
/// The four cases below differ in the page and in nothing else about getting
/// it on screen.
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  sizeView(tester, const Size(900, 1600));
  await tester.pumpWidget(_wrap(page));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Flibler settings show the SDK and change it in dialogs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    controller.setChannel(UfbtUpdateChannel.release);
    addTearDown(() async {
      controller.setChannel(UfbtUpdateChannel.release);
      await controller.setSdkSource(AssemblerSdkSource.unleashed);
      await controller.setCustomIndexUrl('');
    });
    sizeView(tester, const Size(420, 2400));

    await tester.pumpWidget(
      _wrap(AppsSettingsPage(buildRemote: _StubRemote())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flibler'), findsOneWidget);
    expect(find.text('SDK channel'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
    expect(find.text('SDK index'), findsOneWidget);
    expect(find.text('Unleashed'), findsOneWidget);
    // The labels follow the local ufbt state, so only one of each set shows.
    _expectOneAction(const ['Download SDK', 'Update SDK', 'Console']);
    _expectOneAction(const [
      'Download toolchain',
      'Update toolchain',
      'Reinstall toolchain',
      'Console',
    ]);
    expect(find.text('SDK'), findsOneWidget);
    expect(find.text('Toolchain'), findsOneWidget);
    expect(find.byType(AssemblerProgressPanel), findsNothing);

    await _tapRow(tester, 'SDK channel');
    expect(_inDialog('Release'), findsOneWidget);
    await tester.tap(_inDialog('Development'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.channel, UfbtUpdateChannel.dev);
    expect(find.text('Development'), findsOneWidget);

    // The index dialog is the Private DNS shape: known indexes, then a field
    // that only saves an http(s) link.
    await _tapRow(tester, 'SDK index');
    expect(_inDialog(kUnleashedIndexUrl), findsOneWidget);
    expect(_inDialog(kOfficialIndexUrl), findsOneWidget);
    expect(_inDialog('Custom SDK index'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ftp://index.test/x.json');
    await tester.tap(_inDialog('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter an http:// or https:// link to a directory.json'),
      findsOneWidget,
    );
    expect(controller.sdkSource, AssemblerSdkSource.unleashed);
    await tester.enterText(
      find.byType(TextField),
      'https://index.test/directory.json',
    );
    await tester.tap(_inDialog('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.sdkSource, AssemblerSdkSource.custom);
    expect(controller.customIndexUrl, 'https://index.test/directory.json');
    expect(find.text('https://index.test/directory.json'), findsOneWidget);
    await _drainCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flibler settings offer a build backend choice', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    addTearDown(
      () => controller.setPreference(AssemblerBackendPreference.auto),
    );
    sizeView(tester, const Size(420, 2400));

    await tester.pumpWidget(
      _wrap(AppsSettingsPage(buildRemote: _StubRemote())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build with'), findsOneWidget);
    expect(controller.preference, AssemblerBackendPreference.auto);

    // Pinning the server is the only sticky choice; the local controls stay
    // where they are, because that is where the SDK is downloaded.
    await _tapRow(tester, 'Build with');
    expect(_inDialog('Automatic'), findsOneWidget);
    await tester.tap(_inDialog('Build server'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.preference, AssemblerBackendPreference.server);
    expect(controller.backend, AssemblerBackend.server);
    expect(controller.usesServerBuild, isTrue);
    expect(
      find.text('SDK channel'),
      AssemblerController.isSupported ? findsOneWidget : findsNothing,
    );
    expect(find.text('Online · v9.9.9'), findsOneWidget);
    await _drainCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server backend shows live server status', (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'assembler_backend': 'server',
    });
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    addTearDown(
      () => controller.setPreference(AssemblerBackendPreference.auto),
    );
    sizeView(tester, const Size(420, 2400));

    await tester.pumpWidget(
      _wrap(AppsSettingsPage(buildRemote: _StubRemote())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Online · v9.9.9'), findsOneWidget);
    expect(find.text('unlshd-090 · f7'), findsOneWidget);
    expect(find.text('2 in line'), findsOneWidget);
    expect(find.byTooltip('Check server'), findsOneWidget);
    await _drainCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the build settings route scrolls to the Flibler groups', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    await AssemblerController.instance.loadSettings();
    sizeView(tester, const Size(400, 700));

    await tester.pumpWidget(
      _wrap(AppsSettingsPage(focusBuild: true, buildRemote: _StubRemote())),
    );
    await tester.pumpAndSettle();

    final top = tester.getTopLeft(find.text('Flibler')).dy;
    expect(top, lessThan(200), reason: 'Flibler is scrolled to the top');
    await _drainCatalog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Flibler tool stays reachable while this computer can '
      'compile', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AssemblerController.instance;
    await controller.loadSettings();
    final realStatus = controller.readStatus;
    controller.readStatus = () => _ufbtStatus(ready: true);
    controller.refreshStatus();
    addTearDown(() async {
      controller.readStatus = realStatus;
      // setPreference returns early when the value is unchanged, and only a
      // transition to auto clears the fault flag - so leaving auto set would
      // leak markLocalFault into whatever runs next against this singleton.
      await controller.setPreference(AssemblerBackendPreference.server);
      await controller.setPreference(AssemblerBackendPreference.auto);
    });
    await _pumpPage(tester, const ToolsPage());

    // Asserted against a driven status rather than against localReady, which
    // would just restate the implementation and pass either way.
    expect(controller.localReady, isTrue);
    expect(find.text('Flibler'), findsOneWidget);
    expect(find.text(_fliblerSubtitle), findsOneWidget);
    expect(find.text(_fliblerNeedsSdk), findsNothing);

    // Pinning the server moves the catalog, not Flibler: it has no server
    // path, and ensureReady never consults the preference. #248
    await controller.setPreference(AssemblerBackendPreference.server);
    await tester.pumpAndSettle();
    expect(controller.backendChoice.isLocal, isFalse);
    expect(find.text('Flibler'), findsOneWidget);
    expect(find.text(_fliblerSubtitle), findsOneWidget);

    // Same for a catalog build that faulted earlier in the session. #248
    await controller.setPreference(AssemblerBackendPreference.auto);
    controller.markLocalFault(const FileSystemException('toolchain gone'));
    await tester.pumpAndSettle();
    expect(controller.localFaulted, isTrue);
    expect(find.text('Flibler'), findsOneWidget);

    // Without a deployed SDK it cannot build - and says so instead of
    // vanishing, because deploying one brings it back.
    await controller.setPreference(AssemblerBackendPreference.auto);
    controller.readStatus = () => _ufbtStatus(ready: false);
    controller.refreshStatus();
    await tester.pumpAndSettle();
    expect(controller.localReady, isFalse);
    expect(find.text('Flibler'), findsOneWidget);
    expect(find.text(_fliblerNeedsSdk), findsOneWidget);
    expect(find.text(_fliblerSubtitle), findsNothing);
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
