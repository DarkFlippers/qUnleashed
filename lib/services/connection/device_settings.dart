import 'package:flutter/foundation.dart';

import '../settings/persist.dart';
import '../settings/store.dart';

import '../logging.dart';
import '../prefs_reader.dart';

/// How the app behaves around a device link: which transports reconnect on
/// their own and whether the phone's clock is pushed to the Flipper once the
/// startup commands are done.
///
/// Both transports are on by default, and a cable wins: a Flipper on the end
/// of one is the link the user plainly has, so the app forms that intent
/// itself rather than dialling the radio past it.
/// `LinkService._reconcileOnce` states the ordering at the code, and is also
/// where the no-session-held check that keeps a cable from interrupting a
/// live link lives. One rider on "all this decides": a connected USB session
/// seeds that method's hold tier, which ignores the setting, so turning USB
/// off mid-session does not take back a link the app already formed. That set
/// is in memory only, so a restart honours the toggle.
///
/// It was USB-off until a launch with the cable already in dialled Bluetooth
/// instead, which is what the setting decided and nothing else did: the
/// ordering that lets a cable win was already there. On Android the manifest
/// registers `USB_DEVICE_ATTACHED`, so the OS launches the app when a Flipper
/// is plugged in - and the app then declined to connect to the Flipper that
/// had launched it.
///
/// Nothing launches the app on attach anywhere else, so the flip is worth
/// less on the other targets, and on desktop it has a cost: libserialport
/// opens the port exclusively, so the app claims it for the session and
/// another serial client - qFlipper, `ufbt`, a terminal - is refused until
/// the user disconnects. Taken deliberately, because on a desktop the cable
/// is the link people actually use. iOS has no USB transport at all, which is
/// what [usbSupported] is for: the settings screen leaves the row out rather
/// than offer a switch reading on for something that cannot happen.
class DeviceSettings extends PrefsBackedSettings {
  DeviceSettings._();

  static final DeviceSettings instance = DeviceSettings._();

  static const String _prefAutoConnectUsb = 'device.autoconnect.usb';
  static const String _prefAutoConnectBle = 'device.autoconnect.ble';
  static const String _prefSyncTime = 'device.sync_time_on_start';

  /// Both on: see the class doc. Named so [reset] and the fallbacks in
  /// [readFrom] cannot drift from the initialisers below.
  static const bool _defaultAutoConnectUsb = true;
  static const bool _defaultAutoConnectBle = true;
  static const bool _defaultSyncTimeOnStart = true;

  /// Whether this platform has a USB transport at all, so the settings screen
  /// can leave the toggle out instead of offering one that does nothing. iOS
  /// has none - `IosUsbPlatform.loadDevices` returns `const []` and its
  /// `openTransport` throws - and `permissions/center.dart` already encodes
  /// the same fact for the permission centre.
  ///
  /// `defaultTargetPlatform` rather than `Platform.isIOS`, for the reason
  /// `TelemetrySettings.replaySupported` gives: the former is overridable
  /// through `debugDefaultTargetPlatformOverride`, which is how a test pins a
  /// platform, and the latter throws on web.
  static bool get usbSupported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

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

  /// The retry is bounded here, unlike the other two: `LinkService`'s
  /// `_reconcileOnce` awaits load() behind a 250ms debounce fired by cable
  /// events, so a permanently broken store costs one platform round-trip per
  /// plug rather than a loop.
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
