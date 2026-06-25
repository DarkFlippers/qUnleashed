import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'pages/devices/page.dart';
import 'services/connection/foreground_service.dart';
import 'services/connection/notification_service.dart';
import 'services/gps/geolocator_gps_provider.dart';
import 'services/notifications/push_service.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.initialize();
  runApp(const QUnleashedApp());
  _bootstrapAmbientServices();
}

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

  // Android-only: holds a foreground service while connected so the OS does not
  // throttle the process (and drop the BLE link) with the screen off / in the
  // background. No-op on every other platform.
  unawaited(
    _guard(
      'ble foreground service',
      () => BleForegroundService.instance.start(client),
    ),
  );

  // Answers GPS requests from custom firmware apps with the phone's location.
  client.attachGpsResponder(GeolocatorGpsProvider());

  // Answers network requests from custom firmware apps with the phone's
  // internet connection.
  client.attachNetworkResponder();

  unawaited(_guard('push notifications', () => PushService.instance.start()));
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
        home: const DevicePage(),
      ),
    );
  }
}
