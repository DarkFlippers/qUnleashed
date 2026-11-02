import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'refusing_prefs.dart';

/// The remembered-device list that will not save, which is the one failure in
/// the #313 sweep that loses something durable - and, at the bottom, what it
/// does with an entry an older build of the app wrote (#444).
///
/// `_persist` is deliberately not on `persistSetting`; the ruling, and the
/// level it turns on, are written beside the code in `known_devices.dart`.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id, this.transport);

  @override
  final String id;

  @override
  String get name => id;

  @override
  final DeviceTransport transport;
}

FlipperDevice _ble(String id) => FlipperDevice(
  id: id,
  name: id,
  link: FlipperLink.ble,
  source: _Discovered(id, DeviceTransport.ble),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  final known = KnownDevicesStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    // The store is a singleton and outlives any one case.
    await known.load();
    for (final device in [...known.devices]) {
      await known.forget(device);
    }
    clearKeptLines();
  });

  // The level is the whole reason this site did not move onto persistSetting,
  // so it is asserted rather than assumed: `warn` - which is what that
  // function logs - is dropped by a log kept at QLOG_LEVEL=error, and this
  // one has to survive there.
  test('a store that refuses the write says so, at error', () async {
    useRefusingPrefs();

    await known.remember(_ble('b1'));

    expect(
      keptLines.where((l) => l.contains('the store refused the write')),
      isNotEmpty,
    );
    expect(keptLevels, everyElement(KeptLevel.error));
  });

  // #120's rule reaches here too: the list on screen keeps the device, and
  // the user finds out at the next launch, when it is gone.
  test('the device stays in the list for this session', () async {
    useRefusingPrefs();

    await known.remember(_ble('b1'));

    expect(known.devices.map((d) => d.id), contains('b1'));
  });

  test('a write that worked says nothing', () async {
    await known.remember(_ble('b1'));

    expect(keptLines, isEmpty);
    expect(known.devices.map((d) => d.id), contains('b1'));
  });
  // What universal_ble 3.0.0 did to a list of ids written by 2.x. The plugin
  // reported upper-case MACs on Android and reports lower-case now, so an
  // entry stored by an older build of the app names the same Flipper in a
  // spelling nothing coming off the radio will equal. The canonicalisation is
  // on `KnownDevice`'s constructor, so reading is the whole migration.
  group('the id a 2.x build stored', () {
    const stored = '80:E1:27:AA:BB:CC';
    const reported = '80:e1:27:aa:bb:cc';

    KnownDevice entry(String id, String name, String when) =>
        KnownDevice.fromJson({
          'id': id,
          'name': name,
          'lastConnectedAt': when,
        })!;

    test('is canonical by the time it is an entry', () {
      expect(
        entry(stored, 'Flipper Zoe', '2026-10-01T10:00:00.000').id,
        reported,
      );
    });

    test('matches the Flipper the plugin reports today', () {
      // The claim the fix is for: without it this is false, and then the
      // devices page shows the remembered entry and the live device as two,
      // `forget` takes the one that is not there, and the auto-connect target
      // is an id no callback equals.
      final known = entry(stored, 'Flipper Zoe', '2026-10-01T10:00:00.000');

      expect(known.matches(_ble(reported)), isTrue);
    });

    test('and still does not match a different Flipper', () {
      // So the case above cannot pass on a `matches` that answers true.
      final known = entry(stored, 'Flipper Zoe', '2026-10-01T10:00:00.000');

      expect(known.matches(_ble('80:e1:27:11:22:33')), isFalse);
    });

    test('collapses into one entry when both spellings are stored', () {
      // An install that ran a 2.x build and then a 3.x one can hold the same
      // device under both spellings: `remember` deduplicates on `matches`,
      // which did not match across the case change. Newest wins.
      final merged = KnownDevicesStore.newestPerDevice([
        entry(stored, 'the old name', '2026-10-01T10:00:00.000'),
        entry(reported, 'the new name', '2026-10-02T10:00:00.000'),
      ]);

      expect(merged.map((d) => d.id), [reported]);
      expect(merged.single.name, 'the new name');
    });

    test('without collapsing two devices into one', () {
      // The other half: the collapse is per id, not a take(1). Newest first,
      // which is what `lastDevice` reads as the auto-connect target.
      final kept = KnownDevicesStore.newestPerDevice([
        entry(reported, 'older', '2026-10-01T10:00:00.000'),
        entry('80:e1:27:11:22:33', 'newer', '2026-10-02T10:00:00.000'),
      ]);

      expect(kept.map((d) => d.name), ['newer', 'older']);
    });
  });
}
