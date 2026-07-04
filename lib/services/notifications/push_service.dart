import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import 'notification_center.dart';

class PushTopics {
  static const unlRelease = 'unl_release';
  static const ofwRelease = 'ofw_release';
  static const unlDev = 'unl_dev';
  static const ofwDev = 'ofw_dev';

  static const mandatory = [unlRelease, ofwRelease];
  static const dev = [unlDev, ofwDev];
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _prefDevUpdates = 'push.dev_updates_enabled';
  static const _androidChannelId = 'firmware_updates';

  bool _started = false;

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> start() async {
    if (_started || !isSupported) return;
    _started = true;

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await NotificationCenter.instance.initialize();
    await _ensureAndroidChannel();

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: false, sound: true);

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false,
      sound: true,
    );

    for (final topic in PushTopics.mandatory) {
      await messaging.subscribeToTopic(topic);
    }
    await _applyDevSubscription(await isDevUpdatesEnabled());

    FirebaseMessaging.onMessage.listen(_showForeground);
  }

  Future<bool> isDevUpdatesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDevUpdates) ?? false;
  }

  Future<void> setDevUpdatesEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDevUpdates, enabled);
    if (isSupported) await _applyDevSubscription(enabled);
  }

  Future<void> _applyDevSubscription(bool enabled) async {
    final messaging = FirebaseMessaging.instance;
    for (final topic in PushTopics.dev) {
      if (enabled) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    }
  }

  Future<void> _ensureAndroidChannel() async {
    if (!Platform.isAndroid) return;
    await NotificationCenter.instance.plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            'Firmware updates',
            description: 'New Flipper firmware releases and dev builds',
            importance: Importance.high,
          ),
        );
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? 'Update';
    final body = notification?.body ?? '';

    await NotificationCenter.instance.plugin.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          'Firmware updates',
          channelDescription: 'New Flipper firmware releases and dev builds',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}
