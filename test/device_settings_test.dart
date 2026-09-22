import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unopenable_prefs.dart';

/// The third store with the memoised `load()` — see
/// `settings_store_loads_test.dart` for the shape and the other two.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = DeviceSettings.instance;

  // A non-default value for every key, so a test can tell "this came from
  // disk" from "this is the initialiser".
  const stored = <String, Object>{
    'device.autoconnect.usb': true,
    'device.autoconnect.ble': false,
    'device.sync_time_on_start': false,
  };

  Map<String, Object?> snapshot() => {
    'usb': settings.autoConnectUsb,
    'ble': settings.autoConnectBle,
    'sync': settings.syncTimeOnStart,
  };

  late Map<String, Object?> defaults;

  setUp(() {
    LogService.clearHistory();
    SharedPreferences.setMockInitialValues(const {});
    settings.reset();
    defaults = snapshot();
  });

  test('everything stored comes back', () async {
    SharedPreferences.setMockInitialValues(stored);

    await settings.load();

    expect(settings.autoConnectUsb, isTrue);
    expect(settings.autoConnectBle, isFalse);
    expect(settings.syncTimeOnStart, isFalse);
    expect(LogService.history, isEmpty, reason: 'a clean read says nothing');
  });

  test('nothing stored is the documented default, not an error', () async {
    await settings.load();

    expect(snapshot(), defaults);
    expect(LogService.history, isEmpty);
  });

  test('a load notifies', () async {
    SharedPreferences.setMockInitialValues(stored);
    var notifications = 0;
    void count() => notifications++;
    settings.addListener(count);
    addTearDown(() => settings.removeListener(count));

    await settings.load();

    expect(notifications, 1);
    expect(settings.autoConnectUsb, isTrue);
  });

  // One case per key, so the assertion does not depend on which order _load
  // happens to read in.
  for (final bad in stored.keys) {
    final reverted = switch (bad) {
      'device.autoconnect.usb' => 'usb',
      'device.autoconnect.ble' => 'ble',
      _ => 'sync',
    };

    test('a wrong-typed $bad costs that key and nothing else', () async {
      // An int, not a String: that is what pins the `0.0 is T` half of
      // PrefsReader's widening, since without it `99.toDouble() as bool`
      // throws out of the reader and takes the whole store with it.
      SharedPreferences.setMockInitialValues(<String, Object>{
        ...stored,
        bad: 99,
      });

      await settings.load();

      final now = snapshot();
      for (final field in now.keys) {
        expect(
          now[field],
          field == reverted ? defaults[field] : isNot(defaults[field]),
          reason: '$field after a bad $bad',
        );
      }
      expect(settings.loaded, isTrue, reason: 'one key, not the read');
      final kept = LogService.history
          .where((l) => l.contains('[DeviceSettings]'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains(bad));
    });
  }

  // One entry per load, counted and naming every key in read order. With a
  // single bad key a hard-coded "1" and a .first would both pass.
  test('two wrong-typed keys are one entry that names both', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ...stored,
      'device.autoconnect.usb': 99,
      'device.sync_time_on_start': 99,
    });

    await settings.load();

    final kept = LogService.history
        .where((l) => l.contains('[DeviceSettings]'))
        .toList();
    expect(kept, hasLength(1));
    expect(kept.single, contains('ignored 2'));
    expect(
      kept.single,
      contains('device.autoconnect.usb, device.sync_time_on_start'),
    );
    expect(settings.autoConnectBle, isFalse, reason: 'the third still landed');
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
    useUnopenablePrefs();
    addTearDown(settings.reset);

    await expectLater(settings.load(), completes);

    expect(snapshot(), defaults, reason: 'auto-connect still runs on these');
    expect(settings.loaded, isFalse);
    final kept = LogService.history
        .where((l) => l.contains('[DeviceSettings] load failed'))
        .toList();
    expect(kept, hasLength(1), reason: 'labelled, not an anonymous [uncaught]');
    expect(kept.single, contains('could not be opened'));
    // The entry goes through LogService.describe, so it carries whatever
    // stack the rejection had. Here that is the harness's: `flutter test`
    // runs inside a stack_trace chaining zone that supplies one even for a
    // PlatformException, which in the app arrives bare. What this pins is
    // that describe is called at all - swap it for a plain `$e` and the
    // trace disappears for the errors that do carry one.
    expect(kept.single, contains('\n'));
    expect(settings.loaded, isFalse);
  });

  // Not a wish for a retry, a record that there is none. getInstance
  // memoises success for the process and only drops its own memo on failure,
  // and main() reads preferences through three other controllers before
  // runApp - so a store that fails here means the app did not start. A later
  // change to re-read should be a deliberate one.
  test('a failed read is not retried by the next caller', () async {
    useUnopenablePrefs();
    addTearDown(settings.reset);

    await settings.load();
    LogService.clearHistory();
    SharedPreferences.setMockInitialValues(stored);
    await settings.load();

    expect(LogService.history, isEmpty);
    expect(snapshot(), defaults, reason: 'still the defaults, not re-read');
  });

  test('reset puts every field back', () async {
    SharedPreferences.setMockInitialValues(stored);
    await settings.load();
    expect(snapshot(), isNot(defaults));

    settings.reset();

    expect(snapshot(), defaults);
    expect(settings.loaded, isFalse);
  });
}
