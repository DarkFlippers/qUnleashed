import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/logging.dart';
import 'models/models.dart';

/// Media controls Android may receive from a watch or fitness band.
enum MediaRemoteInput {
  previous,
  doublePrevious,
  playPause,
  doublePlayPause,
  next,
  doubleNext,
  volumeUp,
  volumeDown,
}

/// Action sent to a mapped Flipper button.
enum WristRemoteAction {
  tap(Duration.zero),
  hold1s(Duration(seconds: 1)),
  hold2s(Duration(seconds: 2)),
  hold3s(Duration(seconds: 3));

  const WristRemoteAction(this.duration);

  final Duration duration;

  bool get isHold => duration > Duration.zero;
}

/// Gesture timing used by Wrist Remote mappings.
///
/// Keep the user-facing timing copy in `wristRemoteHoldHelp` in sync if this
/// changes.
const Duration wristRemoteDoubleTapDuration = Duration(milliseconds: 400);

/// Dart half of the Android MediaSession bridge used by Wrist Remote.
///
/// It is intentionally page-scoped from the user's point of view:
/// RemoteControlPage starts it when mounted and stops it on dispose. The native
/// MediaSession itself is only active when Wrist Remote is explicitly enabled,
/// so ordinary Android media controls are untouched by default. The native
/// bridge is engine-scoped and survives Activity recreation.
class MediaRemoteBridge {
  MediaRemoteBridge({
    required this.onButton,
    @visibleForTesting bool? supportedOverride,
    @visibleForTesting Future<SharedPreferences> Function()? preferencesLoader,
  }) : _supportedOverride = supportedOverride,
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const MethodChannel _channel = MethodChannel(
    'qunleashed/media_remote',
  );

  // The native MediaSession belongs to the cached FlutterEngine, not to one
  // RemoteControlPage. Page transitions can briefly leave two bridge instances
  // alive, so native ownership and serialization must be process-wide too.
  static Future<void> _nativeSync = Future<void>.value();
  static MediaRemoteBridge? _nativeOwner;
  static bool _nativeActive = false;

  static const String _prefPrefix = 'remote.media.';
  static const String _enabledPref = '${_prefPrefix}enabled';
  static const String _notAssignedValue = '__none__';

  static const Map<MediaRemoteInput, RemoteButton?> _defaults = {
    MediaRemoteInput.previous: RemoteButton.left,
    MediaRemoteInput.doublePrevious: null,
    MediaRemoteInput.playPause: RemoteButton.ok,
    MediaRemoteInput.doublePlayPause: null,
    MediaRemoteInput.next: RemoteButton.right,
    MediaRemoteInput.doubleNext: null,
    MediaRemoteInput.volumeUp: RemoteButton.up,
    MediaRemoteInput.volumeDown: RemoteButton.down,
  };

  final void Function(RemoteButton button, WristRemoteAction action) onButton;
  final bool? _supportedOverride;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Map<MediaRemoteInput, RemoteButton?> _mapping = {..._defaults};
  final Map<MediaRemoteInput, WristRemoteAction> _actionMapping = {};
  final Map<MediaRemoteInput, Timer> _pendingSingleTaps = {};

  SharedPreferences? _preferences;
  Future<void>? _loading;
  bool _started = false;
  bool _enabled = false;

  bool get supported => _supportedOverride ?? Platform.isAndroid;
  bool get enabled => _enabled;

  RemoteButton? buttonFor(MediaRemoteInput input) => _mapping[input];

  WristRemoteAction actionFor(MediaRemoteInput input) =>
      _actionMapping[input] ?? WristRemoteAction.tap;

  Future<void> ensureLoaded() {
    final loading = _loading;
    if (loading != null) return loading;
    final next = _loadWithRetryReset();
    _loading = next;
    return next;
  }

  Future<void> _loadWithRetryReset() async {
    try {
      await _load();
    } catch (_) {
      // A transient SharedPreferences failure must not brick Wrist Remote for
      // the rest of the process. Let the next explicit attempt retry the load.
      _loading = null;
      rethrow;
    }
  }

  Future<void> _load() async {
    final preferences = await _preferencesLoader();
    _preferences = preferences;

    final buttons = RemoteButton.values.asNameMap();
    final actions = WristRemoteAction.values.asNameMap();
    for (final input in MediaRemoteInput.values) {
      final stored = preferences.getString('$_prefPrefix${input.name}');
      if (stored == _notAssignedValue) {
        _mapping[input] = null;
      } else if (stored != null) {
        final parsed = buttons[stored];
        if (parsed != null) _mapping[input] = parsed;
      }

      final storedAction = preferences.getString(
        '$_prefPrefix${input.name}.action',
      );
      final parsedAction = storedAction == null ? null : actions[storedAction];
      if (parsedAction != null) _actionMapping[input] = parsedAction;
    }

    _enabled = preferences.getBool(_enabledPref) ?? false;
    LogService.debug('[WristRemote] mappings loaded; enabled=$_enabled');
  }

  Future<void> setButtonFor(
    MediaRemoteInput input,
    RemoteButton? button,
  ) async {
    await ensureLoaded();
    final key = '$_prefPrefix${input.name}';
    await _write(
      _preferences!.setString(key, button?.name ?? _notAssignedValue),
      key,
    );
    _mapping[input] = button;
    LogService.debug(
      '[WristRemote] mapping ${input.name} -> ${button?.name ?? 'none'}',
    );
  }

  Future<void> setActionFor(
    MediaRemoteInput input,
    WristRemoteAction action,
  ) async {
    await ensureLoaded();
    final key = '$_prefPrefix${input.name}.action';
    await _write(_preferences!.setString(key, action.name), key);
    _actionMapping[input] = action;
    LogService.debug(
      '[WristRemote] mapping ${input.name} action -> ${action.name}',
    );
  }

  Future<void> setEnabled(bool value) async {
    await ensureLoaded();
    if (_enabled == value) return;
    await _write(_preferences!.setBool(_enabledPref, value), _enabledPref);
    _enabled = value;
    LogService.info('[WristRemote] enabled -> $value');
    await _syncNativeState();
  }

  Future<void> resetMappings() async {
    await ensureLoaded();
    _cancelPendingTaps();

    final writes = <Future<bool>>[
      for (final input in MediaRemoteInput.values) ...[
        _preferences!.remove('$_prefPrefix${input.name}'),
        _preferences!.remove('$_prefPrefix${input.name}.action'),
      ],
    ];
    final results = await Future.wait(writes);
    if (results.any((ok) => !ok)) {
      throw StateError('Failed to reset Wrist Remote preferences');
    }

    _mapping
      ..clear()
      ..addAll(_defaults);
    _actionMapping.clear();
    LogService.debug('[WristRemote] mappings reset');
  }

  Future<void> start() async {
    if (!supported || _started) return;

    // Latch ownership before the first await. stop() may run while preferences
    // are loading; in that case the reconciliation below sees _started=false
    // and never creates a MediaSession for a page that has already gone away.
    _started = true;
    try {
      await ensureLoaded();
    } catch (e) {
      _started = false;
      LogService.error('[WristRemote] preference load failed: $e');
      return;
    }
    await _syncNativeState();
  }

  Future<void> stop() async {
    if (!supported) return;
    _started = false;
    _cancelPendingTaps();
    await _syncNativeState();
  }

  Future<void> _syncNativeState() {
    final next = _nativeSync.then((_) => _reconcileNativeState());
    _nativeSync = next.catchError((Object _) {});
    return next;
  }

  Future<void> _reconcileNativeState() async {
    final shouldBeActive = _started && _enabled;

    if (shouldBeActive) {
      final previousOwner = _nativeOwner;
      _nativeOwner = this;
      _channel.setMethodCallHandler(_handleCall);

      if (_nativeActive) {
        if (!identical(previousOwner, this)) {
          LogService.debug('[WristRemote] native ownership transferred');
        }
        return;
      }

      LogService.info('[WristRemote] start requested');
      try {
        await _channel.invokeMethod<void>('start');
        _nativeActive = true;
        LogService.info('[WristRemote] started');
      } catch (e) {
        if (identical(_nativeOwner, this)) {
          _nativeOwner = null;
          _channel.setMethodCallHandler(null);
        }
        LogService.error('[WristRemote] start failed: $e');
      }
      return;
    }

    // A bridge that has already handed ownership to a newer page must never
    // stop that page's engine-scoped MediaSession or clear its channel handler.
    if (!identical(_nativeOwner, this)) return;

    _nativeOwner = null;
    _channel.setMethodCallHandler(null);
    if (!_nativeActive) return;

    LogService.info('[WristRemote] stop requested');
    try {
      await _channel.invokeMethod<void>('stop');
      LogService.info('[WristRemote] stopped');
    } catch (e) {
      LogService.warn('[WristRemote] stop failed: $e');
    } finally {
      _nativeActive = false;
    }
  }

  @visibleForTesting
  Future<dynamic> handleCallForTesting(MethodCall call) => _handleCall(call);

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method != 'button') {
      throw MissingPluginException('${call.method} is not implemented');
    }

    switch (call.arguments) {
      case 'previous':
        _handleTap(MediaRemoteInput.previous, MediaRemoteInput.doublePrevious);
      case 'playPause':
        _handleTap(
          MediaRemoteInput.playPause,
          MediaRemoteInput.doublePlayPause,
        );
      case 'next':
        _handleTap(MediaRemoteInput.next, MediaRemoteInput.doubleNext);
      case 'volumeUp':
        _dispatch(MediaRemoteInput.volumeUp);
      case 'volumeDown':
        _dispatch(MediaRemoteInput.volumeDown);
      default:
        LogService.warn('[WristRemote] unknown media input: ${call.arguments}');
    }
    return null;
  }

  void _handleTap(MediaRemoteInput single, MediaRemoteInput doubleTap) {
    if (buttonFor(doubleTap) == null) {
      _dispatch(single);
      return;
    }

    final pending = _pendingSingleTaps.remove(single);
    if (pending != null) {
      pending.cancel();
      _dispatch(doubleTap);
      return;
    }

    _pendingSingleTaps[single] = Timer(wristRemoteDoubleTapDuration, () {
      _pendingSingleTaps.remove(single);
      _dispatch(single);
    });
  }

  void _dispatch(MediaRemoteInput input) {
    final button = buttonFor(input);
    if (button == null) {
      LogService.debug('[WristRemote] input ${input.name} ignored: unassigned');
      return;
    }
    final action = actionFor(input);
    final suffix = action.isHold
        ? ' (hold ${action.duration.inMilliseconds} ms)'
        : '';
    LogService.debug(
      '[WristRemote] input ${input.name} -> ${button.name}$suffix',
    );
    onButton(button, action);
  }

  void _cancelPendingTaps() {
    for (final timer in _pendingSingleTaps.values) {
      timer.cancel();
    }
    _pendingSingleTaps.clear();
  }

  Future<void> _write(Future<bool> write, String key) async {
    if (!await write) {
      throw StateError('Failed to persist Wrist Remote preference: $key');
    }
  }
}
