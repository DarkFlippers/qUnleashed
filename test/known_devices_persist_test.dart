import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'known_device_ids.dart';
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

    // Upper-case in, lower-case out, so these two also pin the fold on the
    // `fromDevice` arm - the one that writes. Every case in the migration
    // group below reaches `KnownDevice` through `fromJson` instead, so
    // without this the fold could move off the constructor onto that factory
    // with the whole suite green, and a 3.x build would persist an
    // uncanonical id afresh.
    await known.remember(_ble('B1'));

    expect(known.devices.map((d) => d.id), contains('b1'));
  });

  test('a write that worked says nothing', () async {
    await known.remember(_ble('B1'));

    expect(keptLines, isEmpty);
    expect(known.devices.map((d) => d.id), contains('b1'));
  });
  // What universal_ble 3.0.0 did to a store written by a build on 2.x. The
  // plugin reported an upper-case id then - a MAC on Android and Linux,
  // Apple's `uuidString` on iOS and macOS - and reports lower-case now, so an
  // entry an older build stored names the same Flipper in a spelling nothing
  // coming off the radio will equal. The canonicalisation is on
  // `KnownDevice`'s constructor, so reading is the whole migration.
  test('the list the store hands out cannot be written to', () async {
    // A [ChangeNotifier] that hands out its own mutable state has no way to
    // notify about a write it did not make. Only a view stops this: the
    // non-growable list `_load` assigns refuses `add` but takes `[]=`.
    await known.remember(_ble('B1'));

    expect(
      () => known.devices.add(known.devices.first),
      throwsUnsupportedError,
    );
    expect(
      () => known.devices[0] = known.devices.first,
      throwsUnsupportedError,
    );
  });

  group('the id a build on universal_ble 2.x stored', () {
    KnownDevice entry(String id, String name, String when) =>
        KnownDevice.fromJson({
          'id': id,
          'name': name,
          'lastConnectedAt': when,
        })!;

    test('is canonical by the time it is an entry', () {
      // The claim the whole fix rests on. Without it the stored id compares
      // unequal to the live one for the same Flipper, and then a scan never
      // marks the remembered row, the list grows a second row for it, and
      // the auto-connect target is an id no callback equals.
      //
      // There was a case here asserting the composition of this and the one
      // below - that a stored upper-case entry `matches` a live lower-case
      // device. It could never be the only case to fail, so it could not
      // point at a regression; the two folds it composed are each pinned on
      // their own, and the end-to-end version is in
      // `known_devices_migration_test.dart` and `link_autoconnect_test.dart`.
      expect(
        entry(storedById, 'Flipper Zoe', '2026-10-01T10:00:00.000').id,
        reportedById,
      );
    });

    test('and a live id in the old spelling matches a stored one', () {
      // The other direction, which only holds because `matches` folds what it
      // is handed too. It is what `remember` dedupes on, so without the fold
      // an uncanonical live id leaves the stored entry in place and the store
      // holds the same Flipper twice - this bug, by way of this file rather
      // than the plugin.
      final known = entry(
        reportedById,
        'Flipper Zoe',
        '2026-10-01T10:00:00.000',
      );

      expect(known.matches(_ble(storedById)), isTrue);
    });

    test('and still does not match a different Flipper', () {
      // So the case above cannot pass on a `matches` that answers true.
      final known = entry(storedById, 'Flipper Zoe', '2026-10-01T10:00:00.000');

      expect(known.matches(_ble(otherById)), isFalse);
    });

    test('collapses into one entry when both spellings are stored', () {
      // An install that went forward and then back can hold the same device
      // under both spellings: on a build running universal_ble 2.x `remember`
      // deduplicates on `matches`, which compared the raw strings and did not
      // match across the case change, so it adds the platform's spelling
      // beside the canonical one. No released build wrote that pair - the
      // plugin bump and the fold ship together. Newest wins.
      final merged = KnownDevicesStore.newestPerDevice([
        entry(storedById, 'the old name', '2026-10-01T10:00:00.000'),
        entry(reportedById, 'the new name', '2026-10-02T10:00:00.000'),
      ]);

      expect(merged.map((d) => d.id), [reportedById]);
      expect(merged.single.name, 'the new name');
    });

    test('without collapsing two devices into one', () {
      // The other half: the collapse is per id, not a take(1). Newest first,
      // which is what `lastDevice` reads as the auto-connect target.
      final kept = KnownDevicesStore.newestPerDevice([
        entry(reportedById, 'older', '2026-10-01T10:00:00.000'),
        entry(otherById, 'newer', '2026-10-02T10:00:00.000'),
      ]);

      expect(kept.map((d) => d.name), ['newer', 'older']);
    });
  });
}
