import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/routes.dart';
import 'services/assembler/controller.dart';
import 'services/logging.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppRoutes();
  await LogService.initialize();
  await QAppThemeController.instance.loadThemeMode();
  await AssemblerController.instance.loadSettings();
  runApp(const QUnleashedApp());
  bootstrapAmbientServices();
}
