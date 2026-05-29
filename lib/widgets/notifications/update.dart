import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

Future<void> initFirmwareUpdateNotifications({
  bool requestPermissions = true,
  void Function(String? payload)? onNotificationTap,
}) async {
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
  );
  await _plugin.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: (response) {
      onNotificationTap?.call(response.payload);
    },
  );
  final launchDetails = await _plugin.getNotificationAppLaunchDetails();
  final launchResponse = launchDetails?.notificationResponse;
  if (launchDetails?.didNotificationLaunchApp ?? false) {
    onNotificationTap?.call(launchResponse?.payload);
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
  _ready = true;
}

class FirmwareUpdateNotification {
  const FirmwareUpdateNotification._();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'firmware_updates',
      'Firmware updates',
      channelDescription: 'Notifications about new firmware releases',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: 'firmware_updates',
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: 'firmware_updates',
    ),
    linux: LinuxNotificationDetails(urgency: LinuxNotificationUrgency.normal),
  );

  static Future<void> show({
    required String firmwareName,
    required String newVersion,
    required String previousVersion,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: _notificationId(firmwareName),
      title: '$firmwareName Update Available',
      body: '$previousVersion → $newVersion',
      notificationDetails: _details,
      payload: 'firmware_update:${_sourceKey(firmwareName)}',
    );
  }

  static Future<void> showMessage({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  static int _notificationId(String firmwareName) {
    final normalized = firmwareName.toLowerCase();
    if (normalized.contains('unleashed')) return 1002;
    if (normalized.contains('official')) return 1001;
    return 1000;
  }

  static String _sourceKey(String firmwareName) {
    final normalized = firmwareName.toLowerCase();
    if (normalized.contains('unleashed')) return 'unlshd';
    return 'ofw';
  }
}
