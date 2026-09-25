import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/routes.dart';
import 'services/localization/controller.dart';
import 'services/assembler/controller.dart';
import 'services/connection/foreground_service.dart';
import 'services/home_widget/service.dart';
import 'services/home_widget/settings.dart';
import 'services/logging.dart';
import 'theme/theme.dart';

bool _appRunning = false;

Future<void> main() async {
  await _initCore();
  await _runApp();
}

/// Entry point of the engine a home-screen widget starts while the app is not
/// running: the same isolate the activity later attaches to, minus the UI and
/// the ambient services. Only the link keeper comes up, so the cold session
/// survives the screen going dark. `promote` turns it into the full app.
@pragma('vm:entry-point')
Future<void> widgetMain() async {
  await BleForegroundService.instance.start(await _initCore());
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
/// awaits, so even a failure inside it is kept.
Future<FlipperClient> _initCore() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppRoutes();
  await LogService.initialize();
  await QAppThemeController.instance.loadThemeMode();
  await QLocaleController.instance.loadLocale();
  await AssemblerController.instance.loadSettings();
  // The one place both entry points share, so the one place the client is
  // resolved: `widgetMain` hands it to the foreground service, and the home
  // widget serves taps with it on either path. Constructing it touches no
  // disk and no platform channel, so it does not need a catch of its own.
  final client = FlipperOneClient().get();
  HomeWidgetService.instance.install(client: client, promote: _runApp);
  return client;
}

Future<void> _runApp() async {
  if (_appRunning) return;
  _appRunning = true;
  runApp(const QUnleashedApp());
  bootstrapAmbientServices();
  await HomeWidgetSettings.instance.sync();
}
