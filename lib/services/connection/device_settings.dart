import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  bool _loaded = false;
  Future<void>? _loading;

  bool _autoConnectUsb = false;
  bool _autoConnectBle = true;
  bool _syncTimeOnStart = true;

  bool get loaded => _loaded;
  bool get autoConnectUsb => _autoConnectUsb;
  bool get autoConnectBle => _autoConnectBle;
  bool get syncTimeOnStart => _syncTimeOnStart;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _autoConnectUsb = prefs.getBool(_prefAutoConnectUsb) ?? false;
    _autoConnectBle = prefs.getBool(_prefAutoConnectBle) ?? true;
    _syncTimeOnStart = prefs.getBool(_prefSyncTime) ?? true;
    _loaded = true;
    _loading = null;
    notifyListeners();
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
