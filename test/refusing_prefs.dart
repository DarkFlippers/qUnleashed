import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Installs a preferences store that reads back and refuses every write
/// without throwing, until the test ends.
///
/// The failure `persistSetting` could not report before #313, and the one a
/// `catch` never sees. Its doc has which platforms answer this way and why a
/// refused write still reads back correctly; what matters here is that no
/// write mutates [initial], so a second read finds what the next launch would.
///
/// Through the platform interface for the same reason [useUnopenablePrefs] is:
/// `setMockInitialValues` can only describe preferences that write
/// successfully.
void useRefusingPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferencesStorePlatform.instance = _RefusingStore({
    // The legacy API asserts every key a store hands back starts with
    // `flutter.` and strips it, so a store answering in app keys fails the
    // read instead of the write - a different test, passing this one for the
    // wrong reason. Guarded the way `setMockInitialValues` guards it, so an
    // already-prefixed key does not become `flutter.flutter.x`.
    for (final e in initial.entries)
      e.key.startsWith('flutter.') ? e.key : 'flutter.${e.key}': e.value,
  });
  SharedPreferences.resetStatic();
  addTearDown(() {
    SharedPreferences.setMockInitialValues(const {});
    SharedPreferences.resetStatic();
  });
}

/// Reads like the real thing, declines every write.
///
/// The read half is inherited rather than written out: the parent filters on
/// prefix and allow-list the way a real store does, and the three refusals
/// below are the only methods that mutate, so every read path stays honest
/// and every write path answers `false`.
class _RefusingStore extends InMemorySharedPreferencesStore {
  _RefusingStore(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;

  @override
  Future<bool> remove(String key) async => false;

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async => false;
}
