import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'pages/devices/page.dart';
import 'services/connection/notification_service.dart';
import 'services/update/notification_router.dart';
import 'services/update/scheduler.dart';
import 'services/update/update_service.dart';
import 'theme.dart';
import 'widgets/notifications/update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.initialize();
  runApp(const QUnleashedApp());
}

class QUnleashedApp extends StatelessWidget {
  const QUnleashedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: QAppThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'qUnleashed',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(QAppThemeController.instance.activeFirmware),
        navigatorKey: updateNavigatorKey,
        home: const _AppStartup(),
      ),
    );
  }
}

class _AppStartup extends StatefulWidget {
  const _AppStartup();

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      UpdateService.instance.initialize(),
      initFirmwareUpdateNotifications(
        onNotificationTap: handleFirmwareUpdateNotificationPayload,
      ),
      ConnectionNotificationService.instance.start(FlipperOneClient().get()),
    ]);
    await initializeUpdateScheduling();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DevicePage()),
    );
    flushPendingFirmwareUpdateRoute();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/img/firmware/unleashed.jpg',
            width: 110,
            height: 110,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
