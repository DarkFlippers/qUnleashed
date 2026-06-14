import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../services/notifications/notification_center.dart';

Future<void> initFirmwareUpdateNotifications({
  bool requestPermissions = true,
  void Function(String? payload)? onNotificationTap,
}) {
  return NotificationCenter.instance.initialize(
    requestPermissions: requestPermissions,
    onNotificationTap: onNotificationTap,
  );
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
    windows: WindowsNotificationDetails(),
  );

  static Future<void> show({
    required String firmwareName,
    required String newVersion,
    required String previousVersion,
  }) async {
    if (!NotificationCenter.instance.isReady) return;
    await NotificationCenter.instance.plugin.show(
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
    if (!NotificationCenter.instance.isReady) return;
    await NotificationCenter.instance.plugin.show(
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
