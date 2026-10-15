import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/settings/persist.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'kept_lines.dart';
import 'refusing_prefs.dart';

/// A setting the user changed that did not survive being written down.
///
/// Every setter applies the choice to what is on screen first and persists it
/// after, and most are reached by tearing a `Future<void> Function(T)` off
/// into a `ValueChanged<T>` - so the future is discarded, a rejection reached
/// only PlatformDispatcher.onError as an unlabelled `[uncaught]`, and the
/// control took itself back at the next launch with nothing connecting the
/// two. #120.

/// A store that reads back what is there and throws on every write, the way a
/// full disk or a profile the app cannot write to does.
///
/// The other half is `useRefusingPrefs`, whose writes answer `false` instead.
/// Both are failures; only this one reaches a `catch`, which is #313.
class _ReadOnlyStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _values = {};

  @override
  Future<Map<String, Object>> getAll() async => Map.of(_values);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      throw StateError('write failed');

  @override
  Future<bool> remove(String key) async => throw StateError('write failed');

  @override
  Future<bool> clear() async => throw StateError('write failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  /// Makes every write throw from here on.
  ///
  /// The store rather than the method channel: SharedPreferences caches its
  /// instance and the in-memory mock never reaches a channel at all, so a
  /// handler installed there is not on the path a write takes.
  void refuseWrites() {
    SharedPreferencesStorePlatform.instance = _ReadOnlyStore();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    clearKeptLines();
    addTearDown(() => SharedPreferences.setMockInitialValues(const {}));
  });

  Iterable<String> lines(String fragment) =>
      keptLines.where((l) => l.contains(fragment));

  Future<bool> write(String key) =>
      persistSetting(key, (p) => p.setBool(key, true));

  // The two ways a write fails owe the caller the same three things, and owe
  // them identically. Written once so a change to the contract is one edit;
  // what actually differs between the two is in the groups below.
  for (final (how, breakWrites) in <(String, void Function())>[
    ('threw', refuseWrites),
    ('was refused without throwing', useRefusingPrefs),
  ]) {
    group('a write that $how', () {
      test('is kept where a release build can read it', () async {
        breakWrites();

        await write('map.retina');

        expect(lines('did not persist'), isNotEmpty);
      });

      // A log that says "save failed" five times over cannot tell a reader
      // which control went back.
      test('names the setting rather than the operation', () async {
        breakWrites();

        await write('map.retina');

        expect(lines('map.retina'), isNotEmpty);
      });

      // What the caller that *does* read the answer depends on.
      // `HomeWidgetSettings` gates its push on it; nothing else would catch a
      // refusal reported as success.
      test('comes back as false', () async {
        breakWrites();

        expect(await write('map.retina'), isFalse);
      });
    });
  }

  group('a write that threw', () {
    // The caller is usually a torn-off ValueChanged with nowhere to put a
    // rejection, so this has to be the end of it.
    test('does not come back to the caller', () async {
      refuseWrites();

      await expectLater(write('map.retina'), completes);
    });

    test('says what went wrong', () async {
      refuseWrites();

      await write('map.retina');

      expect(lines('write failed'), isNotEmpty);
    });

    // The stack is the only thing naming which setter passed the value, and
    // the message alone names only the key. `LogService.describe` is the
    // house pattern for carrying it into a line.
    test('keeps the stack, not just the message', () async {
      refuseWrites();

      await write('map.retina');

      expect(lines('settings_persist_test.dart'), isNotEmpty);
    });
  });

  // The failure that never reaches the catch, and the whole of #313.
  // `persistSetting`'s own doc has which platforms answer this way.
  group('a write that was refused without throwing', () {
    // Why none of it is visible from inside the session, and why the cases
    // above cannot be written as "read it back and see".
    test('still reads back as though it had worked', () async {
      useRefusingPrefs();

      await write('map.retina');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('map.retina'), isTrue, reason: 'from the cache');
    });

    // There is no exception to quote, so the line has to say why by itself -
    // and it has to say something other than what a throw says, or a reader
    // cannot tell a store that refused from a store that was not there.
    test('says the store refused rather than quoting an exception', () async {
      useRefusingPrefs();

      await write('map.retina');

      expect(lines('the store refused the write'), isNotEmpty);
    });
  });

  group('a write that worked', () {
    test('says nothing', () async {
      await write('map.retina');

      expect(lines('[Settings]'), isEmpty);
    });

    test('actually wrote it', () async {
      await write('map.retina');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('map.retina'), isTrue);
    });

    test('comes back as true', () async {
      expect(await write('map.retina'), isTrue);
    });
  });
}
