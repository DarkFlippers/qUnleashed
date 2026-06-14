import 'dart:async';

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
  _bootstrapAmbientServices();
}

/// Brings up the optional background services (notifications, connection
/// notifier, update scheduler). None of them are required to render the app,
/// so they run independently of the UI and a failure in one never blocks the
/// others — or the main screen. The try/catch here is a safety net for
/// genuinely unexpected runtime errors (IO, OS permission denials), not a
/// substitute for correct per-platform configuration.
void _bootstrapAmbientServices() {
  final client = FlipperOneClient().get();

  unawaited(
    _guard(
      'connection notifier',
      () => ConnectionNotificationService.instance.start(client),
    ),
  );

  // Update directory + notifications must be ready before the scheduler (and
  // before routing a tapped firmware notification), so this strand is ordered.
  unawaited(
    _guard('firmware updates', () async {
      await Future.wait([
        UpdateService.instance.initialize(),
        initFirmwareUpdateNotifications(
          onNotificationTap: handleFirmwareUpdateNotificationPayload,
        ),
      ]);
      flushPendingFirmwareUpdateRoute();
      await initializeUpdateScheduling();
    }),
  );
}

Future<void> _guard(String label, Future<void> Function() task) async {
  try {
    await task();
  } catch (error, stackTrace) {
    LogService.log('Ambient service "$label" failed: $error\n$stackTrace');
  }
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
        home: const DevicePage(),
      ),
    );
  }
}
