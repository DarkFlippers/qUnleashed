import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = DeviceSettings.instance;

  setUp(() {
    LogService.clearHistory();
    SharedPreferences.setMockInitialValues(const {});
    settings.reset();
  });

  /// Swaps in a store whose read throws, and puts the real one back after.
  ///
  /// Through the platform interface rather than `setMockInitialValues`, which
  /// can only describe preferences that are readable - there is no value that
  /// means "the store would not open".
  void unopenableStore() {
    SharedPreferencesStorePlatform.instance = _UnopenableStore();
    SharedPreferences.resetStatic();
    addTearDown(() {
      SharedPreferences.setMockInitialValues(const {});
      SharedPreferences.resetStatic();
      settings.reset();
    });
  }

  test('what is stored comes back', () async {
    SharedPreferences.setMockInitialValues(const {
      'device.autoconnect.usb': true,
      'device.autoconnect.ble': false,
      'device.sync_time_on_start': false,
    });

    await settings.load();

    expect(settings.autoConnectUsb, isTrue);
    expect(settings.autoConnectBle, isFalse);
    expect(settings.syncTimeOnStart, isFalse);
  });

  test('nothing stored is the documented default, not an error', () async {
    await settings.load();

    expect(settings.autoConnectUsb, isFalse);
    expect(settings.autoConnectBle, isTrue);
    expect(settings.syncTimeOnStart, isTrue);
    expect(LogService.history, isEmpty);
  });

  // getBool is a cast, not a checked read, so one value of the wrong type
  // throws partway through. Reading all three before assigning any is what
  // keeps that from leaving a store holding some of what is stored beside
  // some of the defaults - a combination nobody chose and which depends on
  // the order of the lines in _load.
  test('a value of the wrong type costs the read, not half of it', () async {
    SharedPreferences.setMockInitialValues(const {
      'device.autoconnect.usb': true,
      'device.autoconnect.ble': 'yes',
    });

    await settings.load();

    expect(settings.autoConnectUsb, isFalse, reason: 'not the stored true');
    expect(settings.autoConnectBle, isTrue);
    expect(settings.syncTimeOnStart, isTrue);
    expect(
      LogService.history.where((l) => l.contains('[DeviceSettings] load')),
      hasLength(1),
    );
  });

  // The behaviour this pins is the difference between auto-connect working on
  // defaults and auto-connect being dead for the process: DeviceController
  // awaits load() *outside* the try that guards its discovery, and load()
  // memoises - so before this store caught its own failure, one bad read was
  // handed to every later caller and _tryAutoConnect threw on every firing.
  //
  // Both halves are needed. completes pins the reject-to-resolve flip; the
  // history read pins that the catch is not a bare swallow, which would pass
  // the first half just as well.
  test('a store that will not open leaves the defaults and says so', () async {
    unopenableStore();

    await expectLater(settings.load(), completes);

    expect(settings.autoConnectBle, isTrue, reason: 'auto-connect still runs');
    expect(settings.syncTimeOnStart, isTrue);
    expect(settings.autoConnectUsb, isFalse);
    expect(
      LogService.history.where((l) => l.contains('[DeviceSettings] load')),
      hasLength(1),
      reason: 'labelled, rather than an anonymous [uncaught]',
    );
  });

  // Not a wish for a retry - a record that there is none, so a later change
  // to re-read is a deliberate one rather than an accident. The memo latched
  // the same way before this store caught anything; what changed is whether
  // what it latched was a rejection.
  test('a failed read is not retried by the next caller', () async {
    unopenableStore();

    await settings.load();
    LogService.clearHistory();
    await expectLater(settings.load(), completes);

    expect(LogService.history, isEmpty);
    expect(settings.autoConnectBle, isTrue);
  });
}

/// A store that cannot be read at all, like a corrupt or unreadable prefs file.
///
/// `getAll` is what `SharedPreferences.getInstance()` calls, so throwing there
/// fails the whole read rather than one key.
class _UnopenableStore extends SharedPreferencesStorePlatform {
  static const _unreadable = 'the preferences store could not be opened';

  Never _fail() => throw PlatformException(code: 'prefs', message: _unreadable);

  @override
  Future<bool> clear() => _fail();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) => _fail();

  @override
  Future<bool> clearWithPrefix(String prefix) => _fail();

  @override
  Future<Map<String, Object>> getAll() => _fail();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _fail();

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) => _fail();

  @override
  Future<bool> remove(String key) => _fail();

  @override
  Future<bool> setValue(String valueType, String key, Object value) => _fail();
}
