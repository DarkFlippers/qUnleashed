import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../guarded.dart';
import '../localization/l10n.dart';
import '../logging.dart';
import '../permissions/center.dart';
import '../permissions/permission.dart';
import '../permissions/probes.dart';

/// Keeps the BLE link alive on Android while the screen is off or the app is
/// backgrounded.
///
/// The transport layer (flipperlib) is purely reactive: it detects a dropped
/// link and faults, but it cannot stop Android Doze / App-Standby from
/// throttling the process — which is what makes the link die by GATT
/// supervision timeout (status 8) a few seconds/minutes after the screen turns
/// off. A foreground service with `connectedDevice` type keeps the process at
/// high priority and (via [ForegroundTaskOptions.allowWakeLock]) keeps the CPU
/// awake so the main isolate's BLE event loop keeps running.
///
/// CRITICAL TIMING: Android 12+ forbids STARTING a foreground service from the
/// background ([ForegroundServiceStartNotAllowedException]). So the service must
/// be started while the app is in the foreground — which is exactly when a
/// connection is normally established — and then it survives backgrounding on
/// its own. We never try to start it during a background reconnect (that throws
/// and the link stays unprotected); instead we record the desired state and
/// start it the moment the app next returns to the foreground.
///
/// Android-only. A no-op on every other platform (desktop processes are not
/// throttled; iOS background BLE uses CoreBluetooth state restoration instead).
class BleForegroundService with WidgetsBindingObserver {
  static final BleForegroundService instance = BleForegroundService._();
  BleForegroundService._();

  static const int _serviceId = 2002;
  static const String _channelId = 'ble_connection';

  bool _started = false;
  bool _initialized = false;
  // The desired state derived from the connection lifecycle: true while a
  // session is live or being (re)established.
  bool _wantRunning = false;
  String _deviceName = 'Flipper Zero';
  // Whether the app is currently in the foreground. The FGS can only be started
  // while this is true.
  bool _foreground = true;
  // Mirrors the actual foreground service running state so we never issue a
  // redundant start/stop (each is an async platform round-trip).
  bool _serviceRunning = false;
  // Serializes start/stop so overlapping events cannot interleave two platform
  // service requests.
  Future<void> _pending = Future<void>.value();
  // Requested once, lazily, on the first foreground start.
  bool _askedBatteryExemption = false;

  /// Where the two permission answers go.
  ///
  /// Required rather than nullable: all three call sites pass one
  /// (`bootstrapAmbientServices` and `widgetMain`), and an optional one meant
  /// a `?.` on every record plus an ordering dance around the `_started`
  /// guard to paper over it. ADR 0002 asks for injection, not optional
  /// injection.
  ///
  /// `late` because `start` is what supplies it and nothing touches it first.
  late PermissionCenter _permissions;

  StreamSubscription<FlipperConnectionState>? _sub;

  /// Brings the link keeper up.
  ///
  /// [permissions] is where the two permissions this service asks for report
  /// to. `widgetMain()` passes one too: it is the one entry point where this
  /// service runs without a UI, and two of #351's five answers are produced
  /// there, so a centre wired only in `_runApp` would lose exactly the
  /// answers a cold widget-started session produces.
  Future<void> start(
    FlipperClient client, {
    required PermissionCenter permissions,
  }) async {
    _permissions = permissions;
    if (!Platform.isAndroid || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sub = client.connectionStream.listen(_onState);
    // A fresh isolate may find a service left over from a previous process
    // (task removal restarts it sticky). Adopt its actual running state so the
    // reconcile below stops it unless a live session backs it — the
    // notification must never claim a connection that no longer exists.
    if (await FlutterForegroundTask.isRunningService) {
      _serviceRunning = true;
      _wantRunning = client.isConnected || client.isConnecting;
      _sync();
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
    _wantRunning = false;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    // Returning to the foreground is the only moment a deferred start can
    // actually go through ("как только возвращаюсь в графику").
    if (_foreground && !wasForeground) _sync();
  }

  void _onState(FlipperConnectionState state) {
    // Keep the process pinned for the whole session, including the reconnect
    // window where the screen may already be off. Starting as early as
    // `connecting` ensures the service comes up while the user is still in the
    // foreground initiating the connection.
    _wantRunning = state.connected || state.connecting || state.reconnecting;
    if (state.device?.name case final name? when name.isNotEmpty) {
      _deviceName = name;
    }
    _sync();
  }

  // Reconciles the actual service state with [_wantRunning]. Starts only while
  // foregrounded (Android forbids background FGS starts); a desired start while
  // backgrounded is deferred until didChangeAppLifecycleState sees resume.
  void _sync() {
    if (_wantRunning && _foreground && !_serviceRunning) {
      _enqueue('start', _startService);
    } else if (!_wantRunning && _serviceRunning) {
      _enqueue('stop', _stopService);
    } else if (_wantRunning && _serviceRunning) {
      _enqueue('notification update', _updateNotification);
    }
  }

  // Chains the next op after the previous settles so the running state stays
  // consistent regardless of how fast events arrive.
  //
  // The whole `previous.then` goes inside guarded rather than just [op].
  // guarded's own result cannot reject, so wrapping only [op] would be enough
  // today - but `then` on a rejected future skips its callback and propagates,
  // and this is a process-lifetime singleton whose _pending is never reset. One
  // rejected link would leave every later start, stop and update skipped for
  // the life of the process, logging nothing, because guarded would no longer
  // be reached either. Wrapping the predecessor as well heals the chain on the
  // next enqueue instead, which is what the old tail-position catchError did.
  void _enqueue(String what, Future<void> Function() op) {
    final previous = _pending;
    _pending = guarded(
      '[ForegroundService] $what',
      () => previous.then((_) => op()),
    );
  }

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: l10n.notificationChannelBackgroundLink,
        channelDescription: l10n.notificationChannelBackgroundLinkDescription,
        // LOW keeps the notification quiet (no sound/vibration/heads-up) while
        // still being a valid foreground-service notification.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      // No periodic task handler: the service exists only to elevate the
      // process. allowWakeLock keeps the CPU servicing the BLE event loop while
      // the screen is off.
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        autoRunOnBoot: false,
        // A revived service has no isolate behind it (no task handler): it
        // would only show a stale "Connected" notification. Die with the
        // process; the next app start reconnects and starts a truthful one.
        allowAutoRestart: false,
      ),
    );
  }

  Future<void> _startService() async {
    // Re-check under the serialized op: state may have changed while queued.
    if (_serviceRunning || !_wantRunning || !_foreground) return;
    _ensureInitialized();

    // Android 13+ needs runtime notification permission for the foreground
    // notification. Request once; ignore the outcome. Both prompts need an
    // activity — an engine a home-screen widget started has none, and the
    // service must still come up there.
    try {
      var perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        // The answer is read now, where the request's result was discarded.
        // Without this permission Android cannot show the ongoing
        // notification, so the service cannot exist and the link dies the
        // moment the screen sleeps - and the user was told nothing at all.
        // #351.
        perm = await FlutterForegroundTask.requestNotificationPermission();
      }
      // The shared mapper, not a ternary folding every non-granted value into
      // `denied`. On this path there may be no activity to prompt from, and a
      // refusal the user was never offered the chance to make is the same
      // wrong-cause report #351 is about.
      _permissions.record(
        AppPermission.serviceNotification,
        outcomeOfNotificationPermission(perm),
      );

      // Battery optimization exemption keeps the service alive through long
      // background. Ask once; the user may decline.
      if (!_askedBatteryExemption) {
        _askedBatteryExemption = true;
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
    } catch (e, st) {
      // No longer `info`, and that is a consequence of #351 rather than a
      // style change. The outcome used to be ignored by design, so a dropped
      // line cost nothing; it is now the input to a user-visible notice. When
      // this throws - and the comment above says the activity-less
      // `widgetMain()` path is exactly where it does - nothing is recorded,
      // `serviceNotification` stays unknown, Settings -> Device draws
      // nothing, and the link dies when the screen sleeps with the user told
      // nothing. That is the bug this change exists to end, so the one
      // account of it has to survive a release build. `info` does not.
      //
      // Still not `warn`: the service comes up regardless, which is what the
      // battery-exemption comment above is about.
      LogService.caught(
        '[ForegroundService] permission prompt skipped, so the background '
        'link may stop without saying why: ${LogService.describe(e, st)}',
      );
    }

    final serviceTypes = <ForegroundServiceTypes>[
      ForegroundServiceTypes.connectedDevice,
      if (await _locationGranted()) ForegroundServiceTypes.location,
    ];

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: serviceTypes,
      notificationTitle: l10n.notificationBackgroundLinkTitle(_deviceName),
      notificationText: l10n.notificationBackgroundLinkBody,
    );
    if (result is ServiceRequestSuccess) {
      _serviceRunning = true;
    } else if (result is ServiceRequestFailure) {
      // Surface the real cause (PlatformException), not the wrapper's
      // toString - and at a level that survives a release build, since this is
      // the whole of the report. The service failing to start is why the link
      // dies once the screen goes off, and nothing else says so.
      LogService.warn('[ForegroundService] start failed: ${result.error}');
    }
  }

  /// Whether the service may declare `ForegroundServiceTypes.location`.
  ///
  /// The answer is written down as well as returned. It used to be a
  /// `catch (_)` to `false`: the service then started without its location
  /// type, which Android may treat more harshly, and nothing anywhere
  /// said so. #351.
  ///
  /// A throw stays `unknown` rather than `denied`. The read failing is not
  /// the user refusing, and a notice on that guess would tell someone to
  /// go and grant a permission they had already granted.
  Future<bool> _locationGranted() async {
    final LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (e, st) {
      LogService.caught(
        '[ForegroundService] location permission unreadable, starting '
        'without the location type: ${LogService.describe(e, st)}',
      );
      // Nothing recorded. The startup probe may already have established a
      // denial and drawn the notice, and a transient Geolocator failure during
      // a reconnect-driven restart must not take it down - `PermissionCenter`
      // refuses that downgrade for the same reason, and the two paths should
      // not disagree.
      return false;
    }
    // The shared mapper, not a ternary. Nothing in this app ever *asks* for
    // this permission - the call above is a `checkPermission` and there is no
    // `requestPermission` anywhere in this file - so folding every
    // non-granted value into `denied` recorded a refusal the user was never
    // offered, on every fresh Android install, and drew the degraded notice
    // on Settings -> Device for a decision nobody made. `probes.dart` had the
    // rule right and this site broke it.
    final outcome = outcomeOfLocationPermission(permission);
    _permissions.record(AppPermission.serviceLocation, outcome);
    return outcome == PermissionOutcome.granted;
  }

  Future<void> _updateNotification() async {
    if (!_serviceRunning) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: l10n.notificationBackgroundLinkTitle(_deviceName),
        notificationText: l10n.notificationBackgroundLinkBody,
      );
    } catch (e) {
      LogService.warn('[ForegroundService] update failed: $e');
    }
  }

  Future<void> _stopService() async {
    if (!_serviceRunning) return;
    _serviceRunning = false;
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      LogService.warn('[ForegroundService] stop failed: ${result.error}');
    }
  }
}
