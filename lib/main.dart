import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import 'pages/devices/page.dart';
import 'services/connection/foreground_service.dart';
import 'services/connection/notification_service.dart';
import 'services/gps/geolocator_gps_provider.dart';
import 'services/notifications/push_service.dart';
// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  TODO: УДАЛИТЬ В РЕЛИЗЕ — импорт и вызов legacy-миграции ниже,        ║
// ║  затем удалить весь файл services/repository/legacy_migration.dart    ║
// ╚═══════════════════════════════════════════════════════════════════════╝
import 'services/repository/legacy_migration.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.initialize();
  await QAppThemeController.instance.loadThemeMode();
  runApp(const QUnleashedApp());
  _bootstrapAmbientServices();
}

/// genuinely unexpected runtime errors (IO, OS permission denials), not a
/// substitute for correct per-platform configuration.
void _bootstrapAmbientServices() {
  // ╔═════════════════════════════════════════════════════════════════════╗
  // ║  TODO: УДАЛИТЬ В РЕЛИЗЕ — автоматическая миграция старой раскладки  ║
  // ║  Documents/qUnleashed (см. services/repository/legacy_migration.dart)║
  // ╚═════════════════════════════════════════════════════════════════════╝
  unawaited(_guard('legacy layout migration', migrateLegacyLayout));

  final client = FlipperOneClient().get();

  unawaited(
    _guard(
      'connection notifier',
      () => ConnectionNotificationService.instance.start(client),
    ),
  );

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

  // Battery/storage polling is pointless while nobody can see it; freezing it
  // in the background saves both the phone's and the Flipper's battery.
  WidgetsBinding.instance.addObserver(_WatchLifecycleObserver(client));

  unawaited(_guard('push notifications', () => PushService.instance.start()));
}

class _WatchLifecycleObserver with WidgetsBindingObserver {
  _WatchLifecycleObserver(this._client);

  final FlipperClient _client;
  bool _frozen = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (background == _frozen) return;
    _frozen = background;
    if (background) {
      _client.freezeWatch();
    } else {
      _client.unfreezeWatch();
    }
  }
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
    final controller = QAppThemeController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'qUnleashed',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(controller.brightness, controller.accent),
          themeAnimationDuration: Duration.zero,
          home: const DevicePage(),
        );
      },
    );
  }
}
