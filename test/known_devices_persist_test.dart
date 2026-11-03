import 'dart:convert';

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

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
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
  test('a forgotten device is gone from the list and from the disk', () async {
    // Nothing executed `forget` after the teardown sweep in #452: six files
    // ran it incidentally while emptying the store between cases, and none of
    // them asserted anything about it. Those loops were arrangement, not
    // coverage, so removing them left the only path a user has to drop a
    // remembered Flipper - `connect_card.dart`'s row action - with none.
    await known.remember(_ble('b1'));
    await known.remember(_ble('b2'));
    expect(known.devices.map((d) => d.id), ['b2', 'b1'], reason: 'premise');

    await known.forget(known.devices.last);

    expect(known.devices.map((d) => d.id), ['b2']);
    // And durably: `forget` persists, so the next launch does not bring it
    // back. Read through a fresh load rather than through `devices`, which
    // would answer from memory either way.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('known_devices_v1'), isNot(contains('b1')));
    expect(prefs.getString('known_devices_v1'), contains('b2'));
  });

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
        KnownDevice.fromJson(storedEntry(id, name, when))!;

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
      // `known_devices_load_test.dart` and `link_autoconnect_test.dart`.
      expect(
        entry(storedById, 'Flipper Zoe', '2026-10-01T10:00:00.000').id,
        reportedById,
      );
    });

    test('and a live id in the old spelling matches a stored one', () {
      // The other direction, which only holds because `matches` folds what it
      // is handed too. `remember` stopped dedupeing on it in #456 - it
      // prepends and lets `_replace` fold on the id - so what rests on this
      // now is `updateName`, where a miss declines a rename in silence, and
      // `LinkService._onHeard`, where it leaves a remembered row unmarked
      // while the scan can hear the Flipper.
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

    // The write path over a migrated entry, which is the one thing #456
    // changed rather than moved. `remember` used to drop the old entry with
    // `known.matches(device)` and now prepends and lets `_replace` fold on
    // the id. The two agree because `remember` has returned already unless
    // `device.isBle`, and `entry.id` is `canonicalBleDeviceId(device.id)` by
    // the constructor - an argument, where this is the observation.
    //
    // Nothing covered it. The group above pins each fold on its own and the
    // end-to-end load is in `known_devices_load_test.dart`, but a stored
    // entry being written *over* rather than *beside* when that Flipper next
    // connects was left to the two cases composing. What a miss costs is
    // #444's symptom from the write side: one Flipper listed twice under one
    // name, and `forget` removing the row the user did not tap.
    test('is written over, not beside, when that Flipper connects', () async {
      SharedPreferences.setMockInitialValues({
        'known_devices_v1': jsonEncode([
          storedEntry(storedById, 'the stored name', '2026-10-01T10:00:00.000'),
        ]),
      });
      await known.load();
      expect(known.devices.map((d) => d.id), [
        reportedById,
      ], reason: 'premise: the entry loaded, and loaded folded');

      await known.remember(_ble(reportedById));

      // One row. The live id is canonical here because that is what a 3.x
      // plugin reports; the uncanonical direction is pinned by the `matches`
      // case above rather than repeated.
      expect(known.devices, hasLength(1));
      // And it is the fresh entry that survived, not the stored one - which
      // is what makes this a replacement rather than the new entry being
      // dropped as the duplicate.
      expect(known.devices.single.name, reportedById);
    });
  });
}
