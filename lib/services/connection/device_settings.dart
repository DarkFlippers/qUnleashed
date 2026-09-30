import '../settings/persist.dart';
import '../settings/store.dart';

import '../logging.dart';
import '../prefs_reader.dart';

/// How the app behaves around a device link: which transports reconnect on
/// their own and whether the phone's clock is pushed to the Flipper once the
/// startup commands are done.
///
/// USB stays off by default — plugging a cable should not take over a session
/// the user did not ask for; BLE keeps the previous behaviour of reconnecting
/// to the last remembered device.
class DeviceSettings extends PrefsBackedSettings {
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

  bool _autoConnectUsb = _defaultAutoConnectUsb;
  bool _autoConnectBle = _defaultAutoConnectBle;
  bool _syncTimeOnStart = _defaultSyncTimeOnStart;

  bool get autoConnectUsb => _autoConnectUsb;
  bool get autoConnectBle => _autoConnectBle;
  bool get syncTimeOnStart => _syncTimeOnStart;

  @override
  void readFrom(PrefsReader reader) {
    _autoConnectUsb = reader.or(_prefAutoConnectUsb, _defaultAutoConnectUsb);
    _autoConnectBle = reader.or(_prefAutoConnectBle, _defaultAutoConnectBle);
    _syncTimeOnStart = reader.or(_prefSyncTime, _defaultSyncTimeOnStart);

    // The setting reverted to its default and the three toggles this
    // store holds say nothing about it.
    reader.report('[DeviceSettings]');
  }

  /// The retry is bounded here, unlike the other two: _tryAutoConnect awaits
  /// load() on a 250ms debounce fired by cable events, so a permanently
  /// broken store costs one platform round-trip per plug rather than a loop.
  @override
  void onLoadFailed(Object error, StackTrace stack) {
    LogService.warn(
      '[DeviceSettings] load failed: ${LogService.describe(error, stack)}',
    );
  }

  @override
  void resetFields() {
    _autoConnectUsb = _defaultAutoConnectUsb;
    _autoConnectBle = _defaultAutoConnectBle;
    _syncTimeOnStart = _defaultSyncTimeOnStart;
  }

  Future<void> setAutoConnectUsb(bool value) async {
    if (_autoConnectUsb == value) return;
    _autoConnectUsb = value;
    notifyListeners();
    await persistSetting(
      _prefAutoConnectUsb,
      (prefs) => prefs.setBool(_prefAutoConnectUsb, value),
    );
  }

  Future<void> setAutoConnectBle(bool value) async {
    if (_autoConnectBle == value) return;
    _autoConnectBle = value;
    notifyListeners();
    await persistSetting(
      _prefAutoConnectBle,
      (prefs) => prefs.setBool(_prefAutoConnectBle, value),
    );
  }

  Future<void> setSyncTimeOnStart(bool value) async {
    if (_syncTimeOnStart == value) return;
    _syncTimeOnStart = value;
    notifyListeners();
    await persistSetting(
      _prefSyncTime,
      (prefs) => prefs.setBool(_prefSyncTime, value),
    );
  }
}
