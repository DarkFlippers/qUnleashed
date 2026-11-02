import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

import '../guarded.dart';
import '../localization/l10n.dart';
import '../notifications/notification_center.dart';
import '../permissions/center.dart';
import '../permissions/permission.dart';

class ConnectionNotificationService
    with WidgetsBindingObserver, WindowListener {
  static final ConnectionNotificationService instance =
      ConnectionNotificationService._();
  ConnectionNotificationService._();

  static const int _notificationId = 2001;
  static const _channelId = 'connection_errors';
  static const _debounce = Duration(seconds: 2);

  static NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      l10n.notificationChannelConnectionErrors,
      channelDescription: l10n.notificationChannelConnectionErrorsDescription,
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
    windows: WindowsNotificationDetails(),
  );

  FlutterLocalNotificationsPlugin get _plugin =>
      NotificationCenter.instance.plugin;

  bool _started = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _windowFocused = true;

  StreamSubscription<FlipperConnectionState>? _sub;
  Timer? _debounceTimer;
  bool _wasConnected = false;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// The notification permission, read at post time and not cached here.
  ///
  /// `PermissionCenter` is the one store for this, and reading it rather than
  /// keeping an answer of our own is what makes a *later* grant work: `record`
  /// never downgrades a known outcome, `refresh()` re-probes on resume, and a
  /// grant clears the notice. A boolean kept here would hold the refusal for
  /// the life of the process, so a user who turned notifications on in system
  /// settings and came back would get silence for ever - a quieter version of
  /// the bug this gate exists to fix.
  late PermissionCenter _permissions;

  Future<void> start(
    FlipperClient client, {
    required PermissionCenter permissions,
  }) async {
    if (_started) return;
    _started = true;
    _permissions = permissions;

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
      if (NotificationCenter.instance.isReady) {
        unawaited(
          guarded(
            '[Notifications] cancel the connection-lost notification',
            () => _plugin.cancel(id: _notificationId),
          ),
        );
      }
      return;
    }

    // Only notify on connected → disconnected transition
    if (!prev) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!_isInForeground && !_wasConnected) {
        // The timer callback is the last frame there is, so a rejection from
        // `show` has no call site left to catch it and goes to the zone as a
        // fatal (QUNLEASHED-1Y).
        //
        // What is left for `guarded` to catch is the *residue*: a plugin bug, a
        // channel that failed, an authorisation revoked after we asked. The
        // one refusal that was producing all the volume - the user having said
        // no - never reaches here any more, because `_show` returns early on
        // `NotificationCenter.postingRefused`. That matters for the level:
        // `guarded` fixes it at `error`, which `Telemetry._reportGuarded` turns
        // into a `captureEvent` fingerprinted on the label, so a predictable
        // per-disconnect refusal arriving here would be a permanently-open
        // issue accruing an event per disconnect. The residue genuinely earns
        // that level; the refusal never did.
        unawaited(
          guarded(
            '[Notifications] show the connection-lost notification',
            () => _show(state.device?.name ?? 'Flipper Zero'),
          ),
        );
      }
    });
  }

  Future<void> _show(String deviceName) async {
    if (!NotificationCenter.instance.isReady) return;
    // Silently, and before the `_details` getter builds five platform objects.
    // `isDenied` and not `shouldNotice`: a dismissal is a statement about the
    // notice and never about the cause, and this suppresses a competing
    // explanation, which is the distinction `PermissionCenter` names.
    //
    // Letting the post fail instead would be one record per disconnect, for a
    // user whose own setting is working exactly as they set it. #442.
    if (_permissions.isDenied(AppPermission.pushNotifications)) return;
    await _plugin.show(
      id: _notificationId,
      title: l10n.notificationConnectionLostTitle,
      body: l10n.notificationConnectionLostBody(deviceName),
      notificationDetails: _details,
    );
  }
}
