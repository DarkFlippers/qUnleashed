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

  /// Whether a full [awaitApnsToken] wait has already run out this process.
  ///
  /// It keeps the `warn` to one per launch rather than one per Settings
  /// toggle, and shortens every later attempt to a single read: once twenty
  /// seconds have come back empty the next twenty will too, while a token
  /// that does land late is still picked up by that read.
  static bool _apnsTimedOut = false;

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
    // intent at all, for the whole run (Sentry QUNLEASHED-2).
    //
    // `_started` is already true and is never cleared, so there is no second
    // attempt at any of this within the process.
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    // Its own catch, so the two directions stay independent: the cold-start
    // read goes through `convertPlatformException` like every other channel
    // call and can throw, and before this it would have taken the apply below
    // down with it - the same coupling that caused the incident, pointing the
    // other way.
    try {
      _open(await FirebaseMessaging.instance.getInitialMessage());
    } on FirebaseException catch (error) {
      LogService.warn('[Push] cold-start message not read: ${error.code}');
    }

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
    // First, and before the preferences are read. Every Apple path below can
    // sit here for twenty seconds, and reading the four preferences after the
    // wait rather than before it keeps two toggles inside that window from
    // carrying two different snapshots of `active` to the loop in whichever
    // order they happen to finish.
    if (!await _apnsReady()) return;

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

    for (final topic in PushTopics.all) {
      if (active.contains(topic)) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    }
  }

  /// Whether Firebase can be asked to change a topic subscription right now.
  ///
  /// On iOS and macOS a topic call throws without an APNS token - see
  /// [awaitApnsToken] for that contract - so on those two platforms this is
  /// what stands between the loop and the incident. Everywhere else it is
  /// true.
  ///
  /// The three Apple answers, in the order they are cheap to give:
  ///
  ///  * **macOS: never.** APNS registers nothing without an `aps-environment`
  ///    entitlement, and `macos/Runner/{Release,DebugProfile}.entitlements`
  ///    carries none - so the token cannot arrive, and a wait would only
  ///    convert a fast failure into a twenty-second one. 7 of the first 19
  ///    reports on Sentry QUNLEASHED-2 were macOS. Local notifications are
  ///    unaffected, which is why this is not a change to [isSupported]. Delete
  ///    the branch the day the entitlement is added; nothing else here is
  ///    macOS-specific.
  ///  * **Permission not granted: never, until the user changes their mind in
  ///    iOS Settings.** Asked afresh each time rather than remembered from
  ///    [start]: changing their mind there is the recovery path this branch
  ///    exists to leave open, and a snapshot taken at launch would refuse
  ///    them for the rest of the process. `info`, not `warn`: the operation
  ///    did nothing, but the reason is the user's own choice and nobody
  ///    should be alerted to it. [LogService.caught]'s rule excludes this by
  ///    name.
  ///  * **Granted: wait.** [awaitApnsToken] polls, because registration
  ///    completes some time after `requestPermission` returns.
  ///
  /// Leaving the topics alone is the honest outcome when the token never
  /// comes. The preferences have already been written by then - as far as
  /// `persistSetting` got, which logs rather than throws if the write failed -
  /// so the *next launch* applies them once the token is there. Not the next
  /// `start()`: `_started` sees to it that there is no second one this
  /// process. Within the session the retry is any Settings toggle, which
  /// re-enters here and, thanks to [_apnsTimedOut], costs a single read.
  static Future<bool> _apnsReady() async {
    if (Platform.isMacOS) return false;
    if (!Platform.isIOS) return true;

    final messaging = FirebaseMessaging.instance;
    final bool arrived;
    try {
      final status =
          (await messaging.getNotificationSettings()).authorizationStatus;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        LogService.info(
          '[Push] notifications not authorised; topics unchanged',
        );
        return false;
      }

      Future<String?> read() => messaging.getAPNSToken();
      arrived = _apnsTimedOut
          ? await read() != null
          : await awaitApnsToken(read);
    } on FirebaseException catch (error) {
      // Not "not yet" - the channel could not answer the question at all, and
      // retrying that for twenty seconds would report the wrong cause. Narrow
      // on purpose: a `MissingPluginException` is structural and belongs to
      // whoever is reading the report, not to this branch.
      LogService.warn('[Push] could not read the APNS token: ${error.code}');
      return false;
    }

    if (arrived) return true;
    if (!_apnsTimedOut) {
      _apnsTimedOut = true;
      LogService.warn(
        '[Push] authorised but no APNS token after '
        '${_apnsTokenTimeout.inSeconds}s; topics left unchanged',
      );
    }
    return false;
  }

  /// How long [awaitApnsToken] waits for APNS, and how often it looks.
  ///
  /// Apple registers the device with APNS asynchronously, and the token can
  /// arrive seconds after `requestPermission` has returned - longer on a cold
  /// network. 20 seconds covers that.
  ///
  /// It is bounded at all because the token may never come. The iOS
  /// Simulator is the case a developer meets daily and usually never
  /// registers; a denied permission and no network are the rest. An
  /// unbounded wait would hold the caller for the life of the process.
  ///
  /// Nobody watches it elapse. The Settings toggles call this path without
  /// awaiting it ([_applySubscriptions] is reached from four `set*Enabled`
  /// methods that `lib/pages/option/pages/push.dart` fires and forgets), so
  /// the wait is a detached future with no spinner in front of it. The bound
  /// is there because a detached poll should not outlive the user's interest
  /// in its answer, not because anyone is sitting through it.
  static const _apnsTokenTimeout = Duration(seconds: 20);
  static const _apnsTokenPoll = Duration(milliseconds: 200);

  /// Waits for APNS to hand Firebase a device token; says whether it came.
  ///
  /// The contract this is written against: on iOS and macOS,
  /// `subscribeToTopic` and `unsubscribeFromTopic` throw
  /// `FirebaseException(code: 'apns-token-not-set')` while the token is null.
  /// The token arrives *after* `requestPermission` completes, so the apply at
  /// launch raced it and lost - 19 reports from 8 users in four days, Sentry
  /// QUNLEASHED-2.
  ///
  /// The mechanism behind that contract, as of
  /// `firebase_messaging_platform_interface` 4.9.0, is a private
  /// `_APNSTokenCheck` both methods open with, added for flutterfire#10625.
  /// It is a workaround and may be removed; the throw is the part to rely on.
  ///
  /// `getAPNSToken()` is an async method and there is no stream beside it -
  /// `onTokenRefresh` carries the FCM token, not this one - so this polls.
  ///
  /// [reader] is a parameter so the loop can be tested without a platform
  /// channel, and it returns null for "not yet"; it may also throw, which is
  /// [_apnsReady]'s to handle rather than this loop's. The platform check is
  /// the caller's too: off Apple the real reader returns null forever, so
  /// calling this there would spend the timeout and then skip the
  /// subscriptions Android was going to make.
  @visibleForTesting
  static Future<bool> awaitApnsToken(
    Future<String?> Function() reader, {
    Duration timeout = _apnsTokenTimeout,
    Duration poll = _apnsTokenPoll,
  }) async {
    // Stopwatch, not DateTime.now(): the bound above is the whole design, and
    // wall-clock time is not monotonic. A phone that NTP-syncs backwards just
    // after launch - the ordinary case on a freshly booted device, which is
    // also when this runs - would leave a DateTime deadline permanently in
    // the future and poll until the process died.
    final elapsed = Stopwatch()..start();
    while (true) {
      if (await reader() != null) return true;
      if (elapsed.elapsed >= timeout) return false;
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
