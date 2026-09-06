import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../emulate/service.dart';
import '../logging.dart';
import 'cold_link.dart';
import 'widget_key.dart';

export 'widget_key.dart';

/// What the widget caption shows while a tap is being served. The native side
/// turns these into localized text; `idle` restores the key name.
enum WidgetState {
  idle,
  connecting,
  emulating,
  sending,
  sent,
  errorNoDevice,
  errorBusy,
  errorFile,
  errorFailed,
}

/// The colors the launcher paints themed icons with, light and dark.
class MaterialPalette {
  const MaterialPalette({
    required this.backgroundLight,
    required this.backgroundDark,
    required this.foregroundLight,
    required this.foregroundDark,
  });

  final int backgroundLight;
  final int backgroundDark;
  final int foregroundLight;
  final int foregroundDark;
}

/// Dart half of the Android home-screen widgets. The native half owns the
/// widget storage and drawing; this side serves taps — bring the link up cold
/// if needed, run the file through [EmulateService] — and pins or configures
/// widgets on the app's behalf.
class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  static const MethodChannel _channel = MethodChannel('qunleashed/home_widget');
  static const Duration _flashDuration = Duration(seconds: 3);
  static const Duration _sendHold = Duration(milliseconds: 500);

  bool _installed = false;
  Future<void> Function()? _promote;

  /// Widget id waiting for its key. The app shell watches this and opens the
  /// picker on its own archive; it resets the value once the page is up.
  final ValueNotifier<int?> pickRequests = ValueNotifier<int?>(null);

  bool _busy = false;
  int? _servingId;
  int? _cancelledId;
  int? _activeId;
  EmulateService? _active;
  StreamSubscription<AppStateResponse>? _closedSub;
  Timer? _flashTimer;

  bool get supported => Platform.isAndroid;

  /// [promote] brings a cold isolate up to the full app; it runs once, when
  /// the activity attaches to an engine a widget started.
  void install({required Future<void> Function() promote}) {
    _promote = promote;
    if (_installed || !supported) return;
    _installed = true;
    _channel.setMethodCallHandler(_handle);
  }

  Future<bool> pin(WidgetKey key) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('pin', key.toMap()) ?? false;
    } on PlatformException catch (e) {
      LogService.log('[HomeWidget] pin failed: ${e.message}');
      return false;
    }
  }

  /// Mirrors the look settings to the native store, which redraws every
  /// widget with them.
  Future<void> pushSettings(Map<String, Object> settings) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('settings', settings);
    } on PlatformException catch (e) {
      LogService.log('[HomeWidget] settings failed: ${e.message}');
    }
  }

  /// The launcher's themed-icon colors (Android 12+), or null where there
  /// are none.
  Future<MaterialPalette?> palette() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('palette');
      if (raw == null) return null;
      return MaterialPalette(
        backgroundLight: raw['backgroundLight'] as int,
        backgroundDark: raw['backgroundDark'] as int,
        foregroundLight: raw['foregroundLight'] as int,
        foregroundDark: raw['foregroundDark'] as int,
      );
    } on PlatformException catch (e) {
      LogService.log('[HomeWidget] palette failed: ${e.message}');
      return null;
    }
  }

  /// Sends the app to the background, back to whatever the widget was
  /// tapped from.
  Future<void> dismiss() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('dismiss');
    } on PlatformException catch (e) {
      LogService.log('[HomeWidget] dismiss failed: ${e.message}');
    }
  }

  Future<void> configure(int widgetId, WidgetKey key) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('configure', {
        'widgetId': widgetId,
        ...key.toMap(),
      });
    } on PlatformException catch (e) {
      LogService.log('[HomeWidget] configure failed: ${e.message}');
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'promote':
        final promote = _promote;
        if (promote != null) await promote();
        return null;
      case 'send':
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['widgetId'] as int;
        final key = WidgetKey.fromMap(args);
        if (key == null) {
          await _setState(id, WidgetState.errorFile);
          return null;
        }
        unawaited(_onTap(id, key));
        return null;
      case 'cancel':
        final args = call.arguments as Map<Object?, Object?>;
        unawaited(_onCancel(args['widgetId'] as int));
        return null;
      case 'pick':
        final args = call.arguments as Map<Object?, Object?>;
        pickRequests.value = args['widgetId'] as int;
        return null;
    }
    throw MissingPluginException('${call.method} is not implemented');
  }

  /// Drops what a widget is doing: the emulation it holds, or the send still
  /// on its way up. Sent when the taps turn out to be a request for a
  /// different key.
  Future<void> _onCancel(int id) async {
    if (_activeId == id && _active != null) {
      await _stopActive();
      return;
    }
    if (_servingId == id) _cancelledId = id;
  }

  // A tap while another is being served is dropped, not queued: the user is
  // pressing again because nothing seems to happen, not asking for one more
  // send. The one exception is the widget that is currently emulating, whose
  // tap means stop.
  Future<void> _onTap(int id, WidgetKey key) async {
    if (_busy) {
      // The native side already flipped this caption to "connecting"; put it
      // back unless it is the widget being served right now.
      if (id != _servingId) await _setState(id, WidgetState.idle);
      return;
    }
    _busy = true;
    _servingId = id;
    try {
      if (_activeId == id && _active != null) {
        await _stopActive();
        return;
      }
      await _stopActive();
      await _serve(id, key);
    } catch (e) {
      LogService.log('[HomeWidget] tap failed: $e');
      await _flash(id, WidgetState.errorFailed);
    } finally {
      _busy = false;
      _servingId = null;
      _cancelledId = null;
    }
  }

  Future<void> _serve(int id, WidgetKey key) async {
    final client = FlipperOneClient().get();
    await _setState(id, WidgetState.connecting);
    if (!await ColdLink.instance.ensureConnected(client)) {
      await _flash(id, WidgetState.errorNoDevice);
      return;
    }
    if (_cancelledId == id) return;

    final service = EmulateService(client: client);
    final result = await service.start(key.toArchiveKey());
    if (!result.isOk) {
      LogService.log('[HomeWidget] start failed: ${result.error}');
      await _flash(id, _errorState(result.error));
      return;
    }
    if (_cancelledId == id) {
      await service.stop();
      await _setState(id, WidgetState.idle);
      return;
    }

    if (key.holdToSend) {
      await _setState(id, WidgetState.sending);
      await service.sendPress();
      await Future<void>.delayed(_sendHold);
      await service.sendRelease();
      await service.stop();
      await _flash(id, WidgetState.sent);
      return;
    }

    _activeId = id;
    _active = service;
    await _setState(id, WidgetState.emulating);
    _closedSub = client
        .appStateStream()
        .where((s) => s.state == AppState.APP_CLOSED)
        .listen((_) => unawaited(_onClosedOnDevice(service)));
  }

  Future<void> _onClosedOnDevice(EmulateService service) async {
    if (!identical(_active, service)) return;
    final id = _activeId;
    _clearActive();
    if (id != null) await _setState(id, WidgetState.idle);
  }

  Future<void> _stopActive() async {
    final service = _active;
    final id = _activeId;
    if (service == null) return;
    _clearActive();
    await service.stop();
    if (id != null) await _setState(id, WidgetState.idle);
  }

  void _clearActive() {
    _closedSub?.cancel();
    _closedSub = null;
    _active = null;
    _activeId = null;
  }

  WidgetState _errorState(EmulateError? error) => switch (error) {
    EmulateError.busy => WidgetState.errorBusy,
    EmulateError.loadFileFailed => WidgetState.errorFile,
    EmulateError.notConnected => WidgetState.errorNoDevice,
    EmulateError.notEmulatable ||
    EmulateError.appStartFailed ||
    null => WidgetState.errorFailed,
  };

  Future<void> _flash(int id, WidgetState state) async {
    await _setState(id, state);
    _flashTimer?.cancel();
    _flashTimer = Timer(_flashDuration, () {
      if (_activeId != id) unawaited(_setState(id, WidgetState.idle));
    });
  }

  Future<void> _setState(int id, WidgetState state) async {
    try {
      await _channel.invokeMethod<void>('state', {
        'widgetId': id,
        'state': state.name,
      });
    } on PlatformException catch (e) {
      LogService.log('[HomeWidget] state failed: ${e.message}');
    }
  }
}
