import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/persist.dart';

import '../localization/l10n.dart';
import '../logging.dart';
import 'firebase_options.dart';
import 'notification_center.dart';
import 'push_intent.dart';

class PushTopics {
  static const appRelease = 'app_release';
  static const appDev = 'app_dev';
  static const unlRelease = 'unl_release';
  static const ofwRelease = 'ofw_release';
  static const unlDev = 'unl_dev';
  static const ofwDev = 'ofw_dev';

  static const app = [appRelease];
  static const release = [unlRelease, ofwRelease];
  static const dev = [unlDev, ofwDev];
  static const all = [...app, appDev, ...release, ...dev];
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _prefAppReleases = 'push.app_releases_enabled';
  static const _prefAppDev = 'push.app_dev_enabled';
  static const _prefEnabled = 'push.notifications_enabled';
  static const _prefDevUpdates = 'push.dev_updates_enabled';
  static const _androidChannelId = 'firmware_updates';

  bool _started = false;
  static bool _unavailable = false;

  final ValueNotifier<PushIntent?> taps = ValueNotifier<PushIntent?>(null);

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static bool get isUnavailable => _unavailable;

  Future<void> start() async {
    if (_started || !isSupported) return;
    _started = true;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await NotificationCenter.instance.initialize(
        onNotificationTap: (payload) => _dispatch(PushIntent.decode(payload)),
      );
      await _ensureAndroidChannel();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: false, sound: true);

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: false,
        sound: true,
      );
    } catch (error) {
      _unavailable = true;
      // isUnavailable does reach Settings -> Push, but what it renders is
      // "this build is not signed for push", asserted for any throw in the
      // block above - a missing Play Services, a denied notification
      // permission, a transient network failure during Firebase init. A
      // positive claim about the wrong cause is worse than silence, because
      // the reader stops looking. The real one is only here.
      LogService.warn('Push notifications unavailable in this build: $error');
      return;
    }

    // Before the subscriptions, not after. None of these three needs anything
    // from APNS, and when the apply below threw it was them that paid: a
    // launch with no foreground display, no tap handling and no cold-start
    // intent at all, for the whole run (QUNLEASHED-2).
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    _open(await FirebaseMessaging.instance.getInitialMessage());

    await _applySubscriptions();
  }

  void _open(RemoteMessage? message) {
    if (message == null) return;
    _dispatch(PushIntent.fromData(message.data));
  }

  void _dispatch(PushIntent? intent) {
    if (intent != null) taps.value = intent;
  }

  static int _notificationId(RemoteMessage message, PushIntent? intent) {
    final seed = intent == null
        ? message.hashCode
        : Object.hash(intent.type, intent.entry, intent.version);
    return seed & 0x7fffffff;
  }

  Future<bool> isAppReleasesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAppReleases) ?? true;
  }

  Future<void> setAppReleasesEnabled(bool enabled) async {
    await persistSetting(
      _prefAppReleases,
      (prefs) => prefs.setBool(_prefAppReleases, enabled),
    );
    if (isSupported && !_unavailable) await _applySubscriptions();
  }

  Future<bool> isAppDevEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAppDev) ?? false;
  }

  Future<void> setAppDevEnabled(bool enabled) async {
    await persistSetting(
      _prefAppDev,
      (prefs) => prefs.setBool(_prefAppDev, enabled),
    );
    if (isSupported && !_unavailable) await _applySubscriptions();
  }

  Future<bool> isFirmwareReleasesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? true;
  }

  Future<void> setFirmwareReleasesEnabled(bool enabled) async {
    await persistSetting(
      _prefEnabled,
      (prefs) => prefs.setBool(_prefEnabled, enabled),
    );
    if (isSupported && !_unavailable) await _applySubscriptions();
  }

  Future<bool> isFirmwareDevEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDevUpdates) ?? false;
  }

  Future<void> setFirmwareDevEnabled(bool enabled) async {
    await persistSetting(
      _prefDevUpdates,
      (prefs) => prefs.setBool(_prefDevUpdates, enabled),
    );
    if (isSupported && !_unavailable) await _applySubscriptions();
  }

  Future<void> _applySubscriptions() async {
    final messaging = FirebaseMessaging.instance;
    final appEnabled = await isAppReleasesEnabled();
    final appDevEnabled = await isAppDevEnabled();
    final enabled = await isFirmwareReleasesEnabled();
    final devEnabled = await isFirmwareDevEnabled();

    final active = <String>{};
    if (appEnabled) {
      active.addAll(PushTopics.app);
      if (appDevEnabled) active.add(PushTopics.appDev);
    }
    if (enabled) {
      active.addAll(PushTopics.release);
      if (devEnabled) active.addAll(PushTopics.dev);
    }

    // Nothing below this line works on an Apple platform until APNS has
    // registered the device; see [awaitApnsToken]. Leaving the topics alone
    // is the honest outcome when it never does - the preferences are already
    // written, so the next start() applies them once the token is there.
    if (Platform.isIOS || Platform.isMacOS) {
      final arrived = await awaitApnsToken(
        () => FirebaseMessaging.instance.getAPNSToken(),
      );
      if (!arrived) {
        LogService.warn(
          '[Push] no APNS token after $_apnsTokenTimeout; '
          'topic subscriptions left unchanged',
        );
        return;
      }
    }

    for (final topic in PushTopics.all) {
      if (active.contains(topic)) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    }
  }

  /// How long [awaitApnsToken] waits for APNS, and how often it looks.
  ///
  /// Apple registers the device with APNS asynchronously, and the token can
  /// arrive seconds after `requestPermission` has returned - longer on a cold
  /// network. 20 seconds covers that and still bounds a Settings toggle,
  /// which awaits the same path, at something a user would not sit through
  /// twice.
  static const _apnsTokenTimeout = Duration(seconds: 20);
  static const _apnsTokenPoll = Duration(milliseconds: 200);

  /// Waits for APNS to hand Firebase a device token; says whether it came.
  ///
  /// `subscribeToTopic` and `unsubscribeFromTopic` both open with an internal
  /// `_APNSTokenCheck` that throws `apns-token-not-set` on iOS and macOS for
  /// as long as the token is null. That token arrives *after*
  /// `requestPermission` completes, so the apply at launch raced it and lost
  /// - on release builds as much as dev, 14 of the first 19 reports
  /// (QUNLEASHED-2). There is no stream to listen to here, only a getter that
  /// is null until it is not, so this polls.
  ///
  /// The wait is bounded because the token may never come at all: a denied
  /// permission, provisioning with no push entitlement, or no network each
  /// leave it null for the life of the process, and an unbounded wait would
  /// hold the caller there.
  ///
  /// [reader] is a parameter so the loop can be tested without a platform
  /// channel, and it returns null for "not yet". The platform check is the
  /// caller's: off Apple the real reader returns null forever, so calling
  /// this there would spend the timeout and then skip the subscriptions
  /// Android was going to make.
  @visibleForTesting
  static Future<bool> awaitApnsToken(
    Future<String?> Function() reader, {
    Duration timeout = _apnsTokenTimeout,
    Duration poll = _apnsTokenPoll,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (await reader() != null) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(poll);
    }
  }

  Future<void> _ensureAndroidChannel() async {
    if (!Platform.isAndroid) return;
    await NotificationCenter.instance.plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            _androidChannelId,
            l10n.notificationChannelFirmwareUpdates,
            description: l10n.notificationChannelFirmwareUpdatesDescription,
            importance: Importance.high,
          ),
        );
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? l10n.notificationUpdateFallbackTitle;
    final body = notification?.body ?? '';
    final intent = PushIntent.fromData(message.data);

    await NotificationCenter.instance.plugin.show(
      id: _notificationId(message, intent),
      title: title,
      body: body,
      payload: intent?.encode(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          l10n.notificationChannelFirmwareUpdates,
          channelDescription:
              l10n.notificationChannelFirmwareUpdatesDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}
