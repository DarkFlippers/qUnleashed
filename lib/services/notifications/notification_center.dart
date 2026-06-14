import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();
  static const String _windowsAppName = 'qUnleashed';
  static const String _windowsAppUserModelId = 'ru.aperturefox.qUnleashed';
  static const String _windowsGuid = 'd3b5f2a1-7c4e-4b9a-9f1e-2a6c8d0e4f71';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  bool get isReady => _initialized;

  Future<void> initialize({
    bool requestPermissions = true,
    void Function(String? payload)? onNotificationTap,
  }) async {
    if (_initialized) return;

    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: requestPermissions,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: requestPermissions,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: const WindowsInitializationSettings(
        appName: _windowsAppName,
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsGuid,
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response.payload);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      onNotificationTap?.call(launchDetails?.notificationResponse?.payload);
    }

    if (requestPermissions) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: false);
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: false);
    }

    _initialized = true;
  }
}
