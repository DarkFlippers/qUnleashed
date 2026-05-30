import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

class ConnectionNotificationService with WidgetsBindingObserver, WindowListener {
  static final ConnectionNotificationService instance =
      ConnectionNotificationService._();
  ConnectionNotificationService._();

  static const int _notificationId = 2001;
  static const _channelId = 'connection_errors';
  static const _debounce = Duration(seconds: 2);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Connection errors',
      channelDescription: 'Notifications about connection issues',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: _channelId,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: _channelId,
    ),
    linux: LinuxNotificationDetails(urgency: LinuxNotificationUrgency.normal),
  );

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _started = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _windowFocused = true;

  StreamSubscription<FlipperConnectionState>? _sub;
  Timer? _debounceTimer;
  bool _wasConnected = false;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> start(FlipperClient client) async {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);

    if (_isDesktop) {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      _windowFocused = await windowManager.isFocused();
    }

    _sub = client.connectionStream.listen(_onState);
  }

  void stop() {
    if (!_started) return;
    _started = false;

    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) windowManager.removeListener(this);

    _sub?.cancel();
    _sub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  // On desktop: hidden to tray fires AppLifecycleState.hidden;
  // another app focused fires AppLifecycleState.inactive (or onWindowBlur).
  bool get _isInForeground {
    if (_isDesktop) {
      return _windowFocused &&
          _lifecycleState != AppLifecycleState.hidden &&
          _lifecycleState != AppLifecycleState.paused;
    }
    return _lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  @override
  void onWindowFocus() => _windowFocused = true;

  @override
  void onWindowBlur() => _windowFocused = false;

  void _onState(FlipperConnectionState state) {
    final prev = _wasConnected;
    _wasConnected = state.connected;

    if (state.connected) {
      _debounceTimer?.cancel();
      _plugin.cancel(id: _notificationId);
      return;
    }

    // Only notify on connected → disconnected transition
    if (!prev) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!_isInForeground && !_wasConnected) {
        _show(state.device?.name ?? 'Flipper Zero');
      }
    });
  }

  Future<void> _show(String deviceName) async {
    await _plugin.show(
      id: _notificationId,
      title: 'Connection Lost',
      body: 'Lost connection to $deviceName',
      notificationDetails: _details,
    );
  }
}
