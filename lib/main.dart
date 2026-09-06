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
  await _initCore();
  await BleForegroundService.instance.start(FlipperOneClient().get());
}

Future<void> _initCore() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppRoutes();
  await LogService.initialize();
  await QAppThemeController.instance.loadThemeMode();
  await QLocaleController.instance.loadLocale();
  await AssemblerController.instance.loadSettings();
  HomeWidgetService.instance.install(promote: _runApp);
}

Future<void> _runApp() async {
  if (_appRunning) return;
  _appRunning = true;
  runApp(const QUnleashedApp());
  bootstrapAmbientServices();
  await HomeWidgetSettings.instance.sync();
}
