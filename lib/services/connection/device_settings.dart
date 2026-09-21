import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';

/// How the app behaves around a device link: which transports reconnect on
/// their own and whether the phone's clock is pushed to the Flipper once the
/// startup commands are done.
///
/// USB stays off by default — plugging a cable should not take over a session
/// the user did not ask for; BLE keeps the previous behaviour of reconnecting
/// to the last remembered device.
class DeviceSettings extends ChangeNotifier {
  DeviceSettings._();

  static final DeviceSettings instance = DeviceSettings._();

  static const String _prefAutoConnectUsb = 'device.autoconnect.usb';
  static const String _prefAutoConnectBle = 'device.autoconnect.ble';
  static const String _prefSyncTime = 'device.sync_time_on_start';

  /// USB off, BLE on: see the class doc. Named so [reset] and the fallbacks
  /// in [_load] cannot drift from the initialisers below.
  static const bool _defaultAutoConnectUsb = false;
  static const bool _defaultAutoConnectBle = true;
  static const bool _defaultSyncTimeOnStart = true;

  bool _loaded = false;
  Future<void>? _loading;

  bool _autoConnectUsb = _defaultAutoConnectUsb;
  bool _autoConnectBle = _defaultAutoConnectBle;
  bool _syncTimeOnStart = _defaultSyncTimeOnStart;

  bool get loaded => _loaded;
  bool get autoConnectUsb => _autoConnectUsb;
  bool get autoConnectBle => _autoConnectBle;
  bool get syncTimeOnStart => _syncTimeOnStart;

  /// Reads once per process; later callers await the same read.
  ///
  /// Never throws. This memoises, and `DeviceController`'s constructor calls
  /// it unawaited - so a rejection would be an unlabelled uncaught error and
  /// then be handed to every later caller, ending auto-connect for the
  /// process. The defaults are a working fallback.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Read all three before assigning any. `getBool` is a cast rather than
      // a checked read, so a value of the wrong type - an older build, an
      // edited plist - throws partway; assigning as we went would leave the
      // store holding some of what is stored and some of the defaults, with
      // which depending on the order of the lines above.
      final usb = prefs.getBool(_prefAutoConnectUsb) ?? _defaultAutoConnectUsb;
      final ble = prefs.getBool(_prefAutoConnectBle) ?? _defaultAutoConnectBle;
      final sync = prefs.getBool(_prefSyncTime) ?? _defaultSyncTimeOnStart;
      _autoConnectUsb = usb;
      _autoConnectBle = ble;
      _syncTimeOnStart = sync;
      _loaded = true;
      _loading = null;
      notifyListeners();
    } catch (e, st) {
      // With the stack: the cast above names neither the key nor the line,
      // and this replaced an uncaught error that did carry one. KnownDevices
      // and UpdateSettings catch their reads too; MapSettings and the home
      // widget's store still do not - #123.
      LogService.warn('[DeviceSettings] load failed: $e\n$st');
    }
  }

  /// Forgets what was read, so one test does not inherit another's state.
  ///
  /// Without this the first test to drive a failure fixes the result for
  /// every test after it in the same isolate - see [load].
  @visibleForTesting
  void reset() {
    _autoConnectUsb = _defaultAutoConnectUsb;
    _autoConnectBle = _defaultAutoConnectBle;
    _syncTimeOnStart = _defaultSyncTimeOnStart;
    _loaded = false;
    _loading = null;
  }

  Future<void> setAutoConnectUsb(bool value) async {
    if (_autoConnectUsb == value) return;
    _autoConnectUsb = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoConnectUsb, value);
  }

  Future<void> setAutoConnectBle(bool value) async {
    if (_autoConnectBle == value) return;
    _autoConnectBle = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoConnectBle, value);
  }

  Future<void> setSyncTimeOnStart(bool value) async {
    if (_syncTimeOnStart == value) return;
    _syncTimeOnStart = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSyncTime, value);
  }
}
