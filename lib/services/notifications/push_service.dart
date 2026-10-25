import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/persist.dart';

import '../localization/l10n.dart';
import '../logging.dart';
import '../permissions/center.dart';
import '../permissions/permission.dart';
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

  /// Whether FCM topic subscriptions can work here at all.
  ///
  /// Narrower than [isSupported], which gates Firebase init and the local
  /// notification centre - `ConnectionNotificationService` depends on those
  /// running on macOS, so macOS cannot simply drop out of it. What macOS
  /// cannot do is receive a remote push: APNS registers nothing without an
  /// `aps-environment` entitlement and `macos/Runner/*.entitlements` carries
  /// none, so `getAPNSToken()` stays null for the life of every process and a
  /// topic call can only throw. 7 of the first 19 reports on Sentry
  /// QUNLEASHED-2 were macOS.
  ///
  /// Settings reads this too, so the page says push is unavailable on this
  /// platform instead of offering four switches that persist a preference and
  /// then do nothing. Delete the `macOS` half the day the entitlement is
  /// added; nothing else here is macOS-specific.
  ///
  /// Spelled out rather than composed with [isSupported], and on
  /// [defaultTargetPlatform] rather than `dart:io`, for the reason
  /// `DiagnosticsSettings.replaySupported` gives: a test runs on the host, so
  /// `Platform` answers Windows and every branch that hangs off this would be
  /// unreachable from the tests that cover it.
  static bool get topicsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isUnavailable => _unavailable;

  /// Sets [isUnavailable] from a test.
  ///
  /// There is no other way in. `_unavailable` is written in exactly one place
  /// — the Firebase catch in [start] — and a test cannot reach it without a
  /// Firebase, so the Settings → Push branch that renders "this build is not
  /// signed for push" was unreachable from any test. That is the branch #351
  /// is about: it asserted a wrong cause for a denied permission, and the test
  /// written to prove the fix passed either way because the sentence it
  /// searched for could never appear.
  ///
  /// Call `debugSetUnavailable(false)` in a tearDown — this is a static with
  /// no owner, so a test that leaves it set changes the next one.
  @visibleForTesting
  static void debugSetUnavailable(bool value) => _unavailable = value;

  /// Maps Firebase's answer onto the app's.
  ///
  /// `provisional` is iOS delivering quietly without having asked, which
  /// is not a refusal and not something to offer a settings link for.
  /// `notDetermined` has not been answered at all.
  static PermissionOutcome _outcomeOf(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized => PermissionOutcome.granted,
      AuthorizationStatus.provisional => PermissionOutcome.granted,
      AuthorizationStatus.denied => PermissionOutcome.denied,
      AuthorizationStatus.notDetermined => PermissionOutcome.unknown,
    };
  }

  /// Brings push up.
  ///
  /// [permissions] is where the notification permission's answer goes.
  ///
  /// Required rather than nullable: the one caller
  /// (`bootstrapAmbientServices`) always has one, and an optional parameter
  /// bought nothing except a `?.` that could silently drop the answer this
  /// whole change exists to keep.
  Future<void> start({required PermissionCenter permissions}) async {
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
      // The answer is read now. It was discarded here, and the only thing
      // the user was ever told about a denial was Settings -> Push
      // claiming the build is not signed for it - a confident statement
      // of the wrong cause. #351.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: false,
        sound: true,
      );
      permissions.record(
        AppPermission.pushNotifications,
        _outcomeOf(settings.authorizationStatus),
      );

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
    await _applySubscriptions();
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
    await _applySubscriptions();
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
    await _applySubscriptions();
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
    await _applySubscriptions();
  }

  /// The apply currently in flight, joined rather than duplicated.
  ///
  /// Each of the four Settings toggles starts one of these and nobody awaits
  /// any of them, so without this a device whose token never arrives ran four
  /// concurrent twenty-second waits - none of them seeing the latch the first
  /// one was about to set - and then four rounds of six topic calls for a
  /// state that converges on one set.
  ///
  /// Joining is correct rather than merely cheaper because the preferences
  /// are read *after* the wait: a toggle that lands while one of these is
  /// waiting has already persisted its value, so the apply it joins picks
  /// that value up. The window left is a toggle during the topic loop itself,
  /// which is what it was before any of this.
  static Future<void>? _applying;

  Future<void> _applySubscriptions() =>
      _applying ??= _applyOnce().whenComplete(() => _applying = null);

  Future<void> _applyOnce() async {
    // The guard the four setters used to repeat. It lives here now, so a
    // fifth toggle cannot forget it.
    if (!isSupported || _unavailable) return;
    // Before the preferences are read: every Apple path in here can sit for
    // twenty seconds, and reading them afterwards is what lets a concurrent
    // toggle join this apply instead of racing it.
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

    await applyTopics(
      active,
      messaging.subscribeToTopic,
      messaging.unsubscribeFromTopic,
    );
  }

  /// Brings the six topic subscriptions in line with [active], and reports
  /// rather than throws when one of them will not go through.
  ///
  /// [subscribe] and [unsubscribe] are parameters for the reason
  /// [awaitApnsToken]'s [reader] is: `_applyOnce` reaches
  /// `FirebaseMessaging.instance` and is gated behind `isSupported`, which
  /// reads `dart:io`'s `Platform` and is false on every test host, so nothing
  /// above this line can be driven from a test at all.
  ///
  /// **Nothing here may throw, and that is the point.** `start()` awaits this
  /// through `_applySubscriptions`, and `start()` runs inside
  /// `guarded('[Bootstrap] ambient service "push notifications"', ...)`, which
  /// reported a rejection with `Sentry.captureException`. The Settings toggles
  /// reach it a second way, from `void` handlers that await nothing, so there
  /// the rejection went to the zone. Both paths ended in an event carrying an
  /// `exceptions` list, and that is exactly what `ReplayEventProcessor` keys
  /// on: it flushes the replay buffer, and on iOS the session keeps uploading
  /// afterwards. So an offline launch turned §8's "recorded continuously,
  /// uploaded on failure" into "uploaded always" - Sentry QUNLEASHED-2, and
  /// every iOS replay the project has received so far began at one of its
  /// events.
  ///
  /// **The level is not what does that work; the catch is.** All three
  /// `KeptLevel`s land in Sentry Logs through `Telemetry._reportKept`, and a
  /// log carries no `exceptions`, so `warn` is as replay-safe as `caught`.
  /// `warn` then wins on its own merits: `_apnsReady` makes the same
  /// judgement about the same exception type with the same consequence, and
  /// the causes it enumerates - macOS, unauthorised, no token yet - no longer
  /// reach this far. What lands here is the unexplained remainder, which is a
  /// thing to look at rather than a thing to read about later.
  ///
  /// The general fix has since landed (#333, 0013 §6): `Telemetry`'s
  /// `guarded` sink sends an event with a message and no exception, so the
  /// `guarded` route above - a `MissingPluginException` from `_apnsReady`, a
  /// throw from the four preference reads, any other call site - no longer
  /// uploads a replay. What is left on *this* path is the second route: a
  /// rejection from a `void` handler reaches the zone, which is an uncaught
  /// error and does carry an exception. So the catch below is still the thing
  /// standing between an offline toggle and a replay, and the level still is
  /// not.
  @visibleForTesting
  static Future<void> applyTopics(
    Set<String> active,
    Future<void> Function(String) subscribe,
    Future<void> Function(String) unsubscribe,
  ) async {
    // Counted, because the catch is outside the loop. A throw on the nth
    // topic leaves the ones before it applied and the ones after it alone, so
    // "topics left unchanged" would be false for every case but the first -
    // and that matters to the user, not only to the report: the Settings
    // switch has already moved and the preference has already persisted, so a
    // partial apply is a switch that reads off while the topic is still
    // subscribed until the next launch reapplies it.
    //
    // One line and not six: when a topic call fails the reason is usually the
    // connection, so the rest fail the same way. `error.message` rides along
    // because `convertPlatformException` defaults `code` to `unknown` when the
    // native error carries nothing it maps, and `unknown` on its own is not a
    // report. Topic names are constants from [PushTopics] and carry nothing of
    // the user's, so there is no scrubbing question.
    var applied = 0;
    try {
      for (final topic in PushTopics.all) {
        if (active.contains(topic)) {
          await subscribe(topic);
        } else {
          await unsubscribe(topic);
        }
        applied++;
      }
    } on FirebaseException catch (error) {
      // Narrow, like `_apnsReady`'s: a `MissingPluginException` is structural
      // and belongs to whoever reads the report, not to this branch.
      //
      // `all[applied]` and not a second cursor: the catch is reachable only
      // from inside the loop, where the topic that threw is the one the
      // counter has not reached yet. A `stoppedAt` assigned beside the
      // increment says the same thing and has to stay in step with it across
      // the await.
      LogService.warn(
        '[Push] $applied of ${PushTopics.all.length} topic changes applied, '
        'stopped at ${PushTopics.all[applied]}: '
        '${error.code} ${error.message}',
      );
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
  ///  * **macOS: never**, and [topicsSupported] says why.
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
  /// so the *next launch* applies them, and within this one any Settings
  /// toggle re-enters here and costs a single read.
  static Future<bool> _apnsReady() async {
    if (!topicsSupported) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;

    final messaging = FirebaseMessaging.instance;
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

      if (_apnsTimedOut) return await messaging.getAPNSToken() != null;
      if (await awaitApnsToken(messaging.getAPNSToken)) return true;

      _apnsTimedOut = true;
      LogService.warn(
        '[Push] authorised but no APNS token after '
        '${_apnsTokenTimeout.inSeconds}s; topics left unchanged',
      );
      return false;
    } on FirebaseException catch (error) {
      // Not "not yet" - the channel could not answer at all, and retrying
      // that for twenty seconds would report the wrong cause. It covers both
      // reads above, so it names neither. Narrow on purpose: a
      // `MissingPluginException` is structural and belongs to whoever is
      // reading the report, not to this branch.
      LogService.warn('[Push] could not ask iOS about push: ${error.code}');
      return false;
    }
  }

  /// How long [awaitApnsToken] waits for APNS before giving up.
  ///
  /// Registration can take seconds on a cold network, and 20 covers that.
  ///
  /// It is bounded at all because the token may never come: the iOS Simulator
  /// usually never registers, and a denied permission or no network do the
  /// same. Nobody watches it elapse either - the Settings toggles reach
  /// [_applySubscriptions] through four `set*Enabled` methods that
  /// `lib/pages/option/pages/push.dart` fires and forgets, so this is a
  /// detached future with no spinner in front of it. The bound is about how
  /// long a detached poll should outlive the user's interest in its answer,
  /// not about anyone sitting through it.
  static const _apnsTokenTimeout = Duration(seconds: 20);

  /// The first gap between reads, and the ceiling the gap doubles towards.
  ///
  /// A fixed 200ms would make 101 channel round trips of a wait that runs out,
  /// all of them in the busiest twenty seconds the app has. Doubling from 50ms
  /// to a 2s ceiling reaches the same bound in about fifteen, and finds a
  /// token that lands early *sooner* than the fixed gap did.
  static const _apnsPollFirst = Duration(milliseconds: 50);
  static const _apnsPollCap = Duration(seconds: 2);

  /// Waits for APNS to hand Firebase a device token; says whether it came.
  ///
  /// The contract this is written against: on iOS and macOS,
  /// `subscribeToTopic` and `unsubscribeFromTopic` throw
  /// `FirebaseException(code: 'apns-token-not-set')` while the token is null,
  /// and the token arrives *after* `requestPermission` completes - so the
  /// apply at launch raced it and lost. 19 reports from 8 users in four days,
  /// Sentry QUNLEASHED-2.
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
    Duration poll = _apnsPollFirst,
    Duration pollCap = _apnsPollCap,
  }) async {
    // Stopwatch, not DateTime.now(): the bound above is the whole design, and
    // wall-clock time is not monotonic. A phone that NTP-syncs backwards just
    // after launch - the ordinary case on a freshly booted device, which is
    // also when this runs - would leave a DateTime deadline permanently in
    // the future and poll until the process died.
    final elapsed = Stopwatch()..start();
    var gap = poll;
    while (true) {
      if (await reader() != null) return true;
      if (elapsed.elapsed >= timeout) return false;
      await Future<void>.delayed(gap);
      if (gap < pollCap) {
        gap = gap * 2;
        if (gap > pollCap) gap = pollCap;
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
