import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/settings/persist.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A setting the user changed that did not survive being written down.
///
/// Every setter applies the choice to what is on screen first and persists it
/// after, and most are reached by tearing a `Future<void> Function(T)` off
/// into a `ValueChanged<T>` - so the future is discarded, a rejection reached
/// only PlatformDispatcher.onError as an unlabelled `[uncaught]`, and the
/// control took itself back at the next launch with nothing connecting the
/// two. #120.

/// A store that reads back what is there and refuses every write, the way a
/// full disk or a profile the app cannot write to does.
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

  late int logBase;

  /// Makes every write fail from here on.
  ///
  /// The store rather than the method channel: SharedPreferences caches its
  /// instance and the in-memory mock never reaches a channel at all, so a
  /// handler installed there is not on the path a write takes.
  void refuseWrites() {
    SharedPreferencesStorePlatform.instance = _ReadOnlyStore();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    LogService.clearHistory();
    logBase = LogService.history.length;
    addTearDown(() => SharedPreferences.setMockInitialValues(const {}));
  });

  Iterable<String> lines(String fragment) =>
      LogService.history.skip(logBase).where((l) => l.contains(fragment));

  group('a write that failed', () {
    // The caller is usually a torn-off ValueChanged with nowhere to put a
    // rejection, so this has to be the end of it.
    test('does not come back to the caller', () async {
      refuseWrites();

      await expectLater(
        persistSetting('device.auto_connect_usb', (p) async {
          await p.setBool('device.auto_connect_usb', true);
        }),
        completes,
      );
    });

    test('is kept where a release build can read it', () async {
      refuseWrites();

      await persistSetting('device.auto_connect_usb', (p) async {
        await p.setBool('device.auto_connect_usb', true);
      });

      expect(lines('did not persist'), hasLength(1));
    });

    // A log that says "save failed" five times over cannot tell a reader
    // which control went back.
    test('names the setting rather than the operation', () async {
      refuseWrites();

      await persistSetting('map.retina', (p) async {
        await p.setBool('map.retina', true);
      });

      expect(lines('map.retina'), hasLength(1));
    });

    test('says what went wrong', () async {
      refuseWrites();

      await persistSetting('map.retina', (p) async {
        await p.setBool('map.retina', true);
      });

      expect(lines('write failed'), isNotEmpty);
    });
  });

  group('a write that worked', () {
    test('says nothing', () async {
      await persistSetting('map.retina', (p) async {
        await p.setBool('map.retina', true);
      });

      expect(lines('[Settings]'), isEmpty);
    });

    test('actually wrote it', () async {
      await persistSetting('map.retina', (p) async {
        await p.setBool('map.retina', true);
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('map.retina'), isTrue);
    });
  });
}
