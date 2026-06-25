import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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

  StreamSubscription<FlipperConnectionState>? _sub;

  Future<void> start(FlipperClient client) async {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sub = client.connectionStream.listen(_onState);
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
      _enqueue(_startService);
    } else if (!_wantRunning && _serviceRunning) {
      _enqueue(_stopService);
    } else if (_wantRunning && _serviceRunning) {
      _enqueue(_updateNotification);
    }
  }

  // Chains the next op after the previous settles so the running state stays
  // consistent regardless of how fast events arrive.
  void _enqueue(Future<void> Function() op) {
    _pending = _pending.then((_) => op()).catchError((Object e) {
      LogService.log('[ForegroundService] op failed: $e');
    });
  }

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Flipper connection',
        channelDescription:
            'Keeps the Flipper Zero connection alive in the background',
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
      ),
    );
  }

  Future<void> _startService() async {
    // Re-check under the serialized op: state may have changed while queued.
    if (_serviceRunning || !_wantRunning || !_foreground) return;
    _ensureInitialized();

    // Android 13+ needs runtime notification permission for the foreground
    // notification. Request once; ignore the outcome.
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Battery optimization exemption keeps the service alive through long
    // background. Ask once; the user may decline.
    if (!_askedBatteryExemption) {
      _askedBatteryExemption = true;
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.connectedDevice],
      notificationTitle: 'Connected to $_deviceName',
      notificationText: 'Holding the BLE link in the background',
    );
    if (result is ServiceRequestSuccess) {
      _serviceRunning = true;
    } else if (result is ServiceRequestFailure) {
      // Surface the real cause (PlatformException), not the wrapper's toString.
      LogService.log('[ForegroundService] start failed: ${result.error}');
    }
  }

  Future<void> _updateNotification() async {
    if (!_serviceRunning) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Connected to $_deviceName',
        notificationText: 'Holding the BLE link in the background',
      );
    } catch (e) {
      LogService.log('[ForegroundService] update failed: $e');
    }
  }

  Future<void> _stopService() async {
    if (!_serviceRunning) return;
    _serviceRunning = false;
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      LogService.log('[ForegroundService] stop failed: ${result.error}');
    }
  }
}
