// A stored entry the migration cannot read, and the line that says so.
//
// Its own file for the same reason `known_devices_migration_test.dart` is:
// `KnownDevicesStore.load()` memoises on `_loading`, so a process performs
// exactly one real load, and a case that needs a particular store in front of
// it needs a fresh isolate. One file, one load, one claim.
//
// Why the line matters rather than the drop: `_load` reads entry by entry and
// the next mutation writes `_devices` back over the whole stored array, so an
// entry that could not be read here is gone from the store for good. The user
// sees a Flipper they paired simply absent from the list - and since
// `KnownDevice.fromJson` answering null is also what the id migration passes
// through, a silent drop is the migration visibly not applying. ADR 0005 is
// the rule it follows: read entry by entry, and name what was skipped.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/known_devices.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'known_device_ids.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  test(
    'an entry the migration cannot read is counted, not swallowed',
    () async {
      SharedPreferences.setMockInitialValues({
        'known_devices_v1': jsonEncode([
          {
            'id': storedById,
            'name': 'Flipper Zoe',
            'lastConnectedAt': '2026-10-01T10:00:00.000',
          },
          // Two shapes `fromJson` answers null for, which is every way an entry
          // can be lost here: a field of the wrong type, and a timestamp that
          // will not parse.
          {
            'id': 12345,
            'name': 'nope',
            'lastConnectedAt': '2026-10-01T10:00:00.000',
          },
          {'id': otherById, 'name': 'no date'},
        ]),
      });

      await KnownDevicesStore.instance.load();

      // The one readable entry survives, canonicalised.
      expect(KnownDevicesStore.instance.devices.map((d) => d.id), [
        reportedById,
      ]);

      // And the two that did not are named. The count, never the ids - those
      // are Bluetooth addresses.
      expect(
        keptLines.where(
          (line) => line.contains('dropped 2 of 3 stored entries'),
        ),
        isNotEmpty,
      );
      // The exact list, which also says nothing else was kept.
      expect(keptLevels, [KeptLevel.caught]);
      expect(
        keptLines.where((line) => line.contains(otherById)),
        isEmpty,
        reason: 'an address must not reach a kept line',
      );
    },
  );
}
