import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../prefs_reader.dart';

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
    final PrefsReader reader;
    try {
      reader = PrefsReader(await SharedPreferences.getInstance());
    } catch (e, st) {
      // See MapSettings for the long version: getInstance is the only throw,
      // it carries a stack only when the error is an Error, the fields are
      // all-or-nothing because every read below goes through PrefsReader, and
      // _loading is released so the next caller reads again - see there for
      // why #124 changed that answer.
      //
      // The retry is bounded here: _tryAutoConnect awaits load() on a 250ms
      // debounce fired by cable events, so a permanently broken store costs
      // one platform round-trip per plug rather than a loop.

      _loading = null;
      LogService.warn(
        '[DeviceSettings] load failed: ${LogService.describe(e, st)}',
      );
      return;
    }

    _autoConnectUsb = reader.or(_prefAutoConnectUsb, _defaultAutoConnectUsb);
    _autoConnectBle = reader.or(_prefAutoConnectBle, _defaultAutoConnectBle);
    _syncTimeOnStart = reader.or(_prefSyncTime, _defaultSyncTimeOnStart);
    _loaded = true;

    // The setting reverted to its default and the three toggles this
    // store holds say nothing about it.
    reader.report('[DeviceSettings]');
    notifyListeners();
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
