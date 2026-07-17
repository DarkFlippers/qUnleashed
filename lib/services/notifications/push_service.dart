import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import 'notification_center.dart';

class PushTopics {
  static const appRelease = 'app_release';
  static const unlRelease = 'unl_release';
  static const ofwRelease = 'ofw_release';
  static const unlDev = 'unl_dev';
  static const ofwDev = 'ofw_dev';

  static const app = [appRelease];
  static const release = [unlRelease, ofwRelease];
  static const dev = [unlDev, ofwDev];
  static const all = [...app, ...release, ...dev];
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _prefAppReleases = 'push.app_releases_enabled';
  static const _prefEnabled = 'push.notifications_enabled';
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

    await _applySubscriptions();

    FirebaseMessaging.onMessage.listen(_showForeground);
  }

  Future<bool> isAppReleasesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAppReleases) ?? true;
  }

  Future<void> setAppReleasesEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAppReleases, enabled);
    if (isSupported) await _applySubscriptions();
  }

  Future<bool> isFirmwareReleasesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? true;
  }

  Future<void> setFirmwareReleasesEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
    if (isSupported) await _applySubscriptions();
  }

  Future<bool> isFirmwareDevEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDevUpdates) ?? false;
  }

  Future<void> setFirmwareDevEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDevUpdates, enabled);
    if (isSupported) await _applySubscriptions();
  }

  Future<void> _applySubscriptions() async {
    final messaging = FirebaseMessaging.instance;
    final appEnabled = await isAppReleasesEnabled();
    final enabled = await isFirmwareReleasesEnabled();
    final devEnabled = await isFirmwareDevEnabled();

    final active = <String>{};
    if (appEnabled) active.addAll(PushTopics.app);
    if (enabled) {
      active.addAll(PushTopics.release);
      if (devEnabled) active.addAll(PushTopics.dev);
    }

    for (final topic in PushTopics.all) {
      if (active.contains(topic)) {
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
