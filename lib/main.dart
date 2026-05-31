import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'pages/devices/page.dart';
import 'services/connection/notification_service.dart';
import 'services/update/notification_router.dart';
import 'services/update/scheduler.dart';
import 'services/update/update_service.dart';
import 'theme.dart';
import 'widgets/notifications/update.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UpdateService.instance.initialize();
  await initFirmwareUpdateNotifications(
    onNotificationTap: handleFirmwareUpdateNotificationPayload,
  );
  await initializeUpdateScheduling();
  await ConnectionNotificationService.instance.start(FlipperOneClient().get());
  runApp(const QUnleashedApp());
}

class QUnleashedApp extends StatefulWidget {
  const QUnleashedApp({super.key});

  @override
  State<QUnleashedApp> createState() => _QUnleashedAppState();
}

class _QUnleashedAppState extends State<QUnleashedApp> {
  final _themeController = QAppThemeController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      flushPendingFirmwareUpdateRoute();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) => MaterialApp(
        title: 'qUnleashed',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(_themeController.activeFirmware),
        navigatorKey: updateNavigatorKey,
        home: const DevicePage(),
      ),
    );
  }
}
