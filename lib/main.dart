import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/routes.dart';
import 'app/shutdown.dart';
import 'services/localization/controller.dart';
import 'services/assembler/controller.dart';
import 'services/connection/foreground_service.dart';
import 'services/permissions/center.dart';
import 'services/permissions/permission.dart';
import 'services/permissions/probes.dart';
import 'services/storage/permissions.dart';
import 'services/home_widget/service.dart';
import 'services/home_widget/settings.dart';
import 'services/logging.dart';
import 'services/telemetry/settings.dart';
import 'services/telemetry/telemetry.dart';
import 'theme/theme.dart';

bool _appRunning = false;

Future<void> main() async {
  await _runApp(await _initCore());
}

/// What `_initCore` built, for the two entry points that go on to use
/// different parts of it.
///
/// It was the client alone until reporting arrived. A record rather than a
/// second global, because the whole point of the switch living in an object is
/// that `_runApp` can hand it to the settings screen - and because CLAUDE.md's
/// standing warning is that anything assembled in `_runApp` does not exist in
/// `widgetMain()`. Assembling both here is what keeps the headless isolate
/// reporting at all.
typedef AppCore = ({
  FlipperClient client,
  Telemetry telemetry,
  PermissionCenter permissions,
});

/// Entry point of the engine a home-screen widget starts while the app is not
/// running: the same isolate the activity later attaches to, minus the UI and
/// the ambient services. Only the link keeper comes up, so the cold session
/// survives the screen going dark. `promote` turns it into the full app.
@pragma('vm:entry-point')
Future<void> widgetMain() async {
  final core = await _initCore();
  // The centre goes in here too. CLAUDE.md's standing warning is that
  // anything assembled in `_runApp` does not exist on this path, and this
  // service is where two of the five permissions in #351 are answered - so a
  // centre wired only in `_runApp` would lose exactly the answers a cold
  // widget-started session produces.
  //
  // No observer is installed here and none should be: there is no screen to
  // update, and the activity that attaches later runs `_runApp`, which calls
  // `install()` on this same object.
  await BleForegroundService.instance.start(
    core.client,
    permissions: core.permissions,
  );
}

/// Everything that has to exist before there is a UI.
///
/// Nothing in here may reject. `main()` awaits it ahead of `runApp`, and
/// `widgetMain()` awaits it with no UI at all, so a throw is not a setting
/// that falls back - it is an app that never appears, on either entry point.
/// Every call below that touches the disk or a platform channel carries its
/// own catch for that reason: the three preference reads and the assembler's
/// status probe (#124), and the BLE log level inside `initialize`.
///
/// `LogService.initialize()` goes first so the rest have somewhere to report
/// to. Its own uncaught-error handlers are installed before anything it
/// awaits, so even a failure inside it is kept. `Telemetry.start` goes after
/// it for the other half of the same reason: the handlers Sentry chains to are
/// the ones it finds in the two error slots, so it has to find
/// `LogService`'s. ADR 0013 §2.
Future<AppCore> _initCore() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppRoutes();
  await LogService.initialize();
  await QAppThemeController.instance.loadThemeMode();
  await QLocaleController.instance.loadLocale();
  await AssemblerController.instance.loadSettings();
  // Both never throw, which is what lets them sit on a path that must not:
  // the switch defaults to on when its store will not open, and `start`
  // catches its own init. Here rather than in `_runApp` because the
  // home-screen widget's isolate never reaches `_runApp`, and a crash in a
  // cold BLE session is one of the failures this exists to catch.
  final telemetry = Telemetry(settings: DiagnosticsSettings());
  await telemetry.start();
  // The one place both entry points share, so the one place the client is
  // resolved: `widgetMain` hands it to the foreground service, and the home
  // widget serves taps with it on either path. Constructing it touches no
  // disk and no platform channel, so it does not need a catch of its own.
  final client = FlipperOneClient().get();
  // Here and not in `_runApp`, because `widgetMain()` never reaches `_runApp`
  // and the foreground service it starts answers two of these five
  // permissions. Constructing it touches no disk and no platform channel -
  // the probes are closures nothing has called yet - so it is safe on a path
  // that must never throw. #351.
  final permissions = PermissionCenter(probes: buildPermissionProbes(client));
  // The storage permission is answered deep inside `paths.dart`, on a path
  // the home-screen widget's isolate and a dozen unit tests also reach. A
  // sink rather than an import is what lets those paths stay unchanged.
  reportStoragePermissionTo(
    (outcome) => permissions.record(AppPermission.storage, outcome),
  );
  final core = (client: client, telemetry: telemetry, permissions: permissions);
  HomeWidgetService.instance.install(
    client: client,
    promote: () => _runApp(core),
  );
  return core;
}

/// Puts the UI up around [core], the one `_initCore` assembled.
///
/// Taking it as a parameter rather than reading it back is what keeps the
/// comment above true: `promote` closes over the core its own `_initCore`
/// returned, so neither entry point resolves a second client and neither
/// starts the SDK twice.
Future<void> _runApp(AppCore core) async {
  if (_appRunning) return;
  _appRunning = true;
  final client = core.client;
  // Wrapped rather than wrapping inside `app.dart`, so the file that builds
  // the UI still names no Sentry type - §2's import rule - and so the recorder
  // has one stable mount point above every route.
  //
  // Not for the reason this comment used to give. It claimed the placement
  // kept `MaterialApp`'s theme and locale rebuilds from running through the
  // wrapper; above `MaterialApp` the wrapper instead depends on the **root**
  // `MediaQueryData`, which changes on every frame of a keyboard show or hide
  // and every resize frame - strictly more often than a theme change. The work
  // either way is one status allocation and a compare, so the efficiency claim
  // was both wrong and immaterial; it is written down so nobody optimises
  // toward it.
  //
  // `Telemetry.wrap` hands back the child untouched when there is no DSN.
  runApp(
    core.telemetry.wrap(
      QUnleashedApp(
        client: client,
        diagnostics: core.telemetry.settings,
        permissions: core.permissions,
        navigatorObservers: core.telemetry.navigatorObservers,
      ),
    ),
  );
  bootstrapAmbientServices(core.permissions);
  // Here and not in _initCore: widgetMain() never reaches _runApp and has no
  // window to hook, and _initCore must never throw. See AppShutdown.
  await AppShutdown(client, core.telemetry).install();
  await HomeWidgetSettings.instance.sync();
}
