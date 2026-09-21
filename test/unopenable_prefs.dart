import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Installs a preferences store that cannot be read, until the test ends.
///
/// Through the platform interface rather than `setMockInitialValues`, which
/// can only describe preferences that are readable — there is no value that
/// means "the store would not open". `getAll` is what
/// `SharedPreferences.getInstance()` calls, so a throw there fails the whole
/// read rather than one key.
///
/// Shared because three settings stores have the same memoised `load()`, and
/// a rejection from any of them is latched and handed to every later caller
/// for the life of the process — see #123.
void useUnopenablePrefs() {
  SharedPreferencesStorePlatform.instance = _UnopenableStore();
  SharedPreferences.resetStatic();
  addTearDown(() {
    SharedPreferences.setMockInitialValues(const {});
    SharedPreferences.resetStatic();
  });
}

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
