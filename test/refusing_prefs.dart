import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Installs a preferences store that reads back and refuses every write
/// without throwing, until the test ends.
///
/// The failure #313 is about. On Android the legacy backend returns
/// `Editor.commit()` straight through and that is `false` when the write to
/// persistent storage did not land; Windows and Linux answer the same way for
/// a preferences file they cannot write. Nothing throws, so a `catch` never
/// sees it.
///
/// What makes it invisible is the read: `SharedPreferences` updates its own
/// cache before it asks the store and does not roll back, so the setting reads
/// back as the user left it for the rest of the session. [initial] is what a
/// *fresh* read would find, which is the next launch's answer and the one that
/// differs.
///
/// Through the platform interface for the same reason [useUnopenablePrefs]
/// is: `setMockInitialValues` can only describe preferences that write
/// successfully.
void useRefusingPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferencesStorePlatform.instance = _RefusingStore({
    // The legacy API asserts every key a store hands back starts with
    // `flutter.` and strips it, so a store that answers in app keys fails the
    // read instead of the write - which is a different test, and passes this
    // one for the wrong reason. `setMockInitialValues` prefixes them the same
    // way, and is not usable here because it cannot describe a refusal.
    for (final e in initial.entries) 'flutter.${e.key}': e.value,
  });
  SharedPreferences.resetStatic();
  addTearDown(() {
    SharedPreferences.setMockInitialValues(const {});
    SharedPreferences.resetStatic();
  });
}

class _RefusingStore extends SharedPreferencesStorePlatform {
  _RefusingStore(this._stored);

  /// What is on disk, which no write here ever changes.
  final Map<String, Object> _stored;

  @override
  Future<Map<String, Object>> getAll() async => Map.of(_stored);

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async => Map.of(_stored);

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) async => {
    for (final e in _stored.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;

  @override
  Future<bool> remove(String key) async => false;

  @override
  Future<bool> clear() async => false;

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async => false;

  @override
  Future<bool> clearWithPrefix(String prefix) async => false;
}
