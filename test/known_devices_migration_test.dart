// The one load a process gets, with a store written by a 2.x build in front
// of it.
//
// Its own file, and that is the whole point of the file. `KnownDevicesStore`
// is a singleton whose `load()` memoises on `_loading`, so a process performs
// exactly one real load - and `known_devices_persist_test.dart` spends its on
// an empty store in `setUp`, which is why the collapse had to be reachable as
// `newestPerDevice` separately. A fresh suite file is a fresh isolate and so a
// fresh memo, so the load path *is* testable; what is impossible is reaching
// it twice.
//
// Measured: with `_load` reverted to the pre-fix `parsed.sort(); _devices =
// parsed;`, this is the only case in the repository that fails. #444.
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

  // Two spellings of one Flipper, which is the shape a round trip leaves: a
  // store this build canonicalised, a rollback to one on universal_ble 2.x
  // that re-remembers the device in the platform's own case beside it, and
  // then this build again. No released build wrote that pair - the plugin
  // bump and the fold ship together - and a restored or hand-edited store
  // gets there too.
  test(
    'a store written by a 2.x build loads as one canonical device',
    () async {
      SharedPreferences.setMockInitialValues({
        'known_devices_v1': jsonEncode([
          {
            'id': storedById,
            'name': 'the older name',
            'lastConnectedAt': '2026-10-01T10:00:00.000',
          },
          {
            'id': reportedById,
            'name': 'the newer name',
            'lastConnectedAt': '2026-10-02T10:00:00.000',
          },
        ]),
      });

      await KnownDevicesStore.instance.load();
      final known = KnownDevicesStore.instance;

      // One row, not two. This is the user-visible half: `LinkService.entries`
      // is a one-to-one comprehension over this list, so two entries here are
      // two rows for one Flipper - and `forget` on either removes both.
      expect(known.devices.map((d) => d.id), [reportedById]);
      // Newest first, because that is what `lastDevice` reads and what the
      // auto-connect target is.
      expect(known.lastDevice?.name, 'the newer name');

      // The collapse says so. It is the only place this app drops a remembered
      // device without being asked, and the only evidence the migration ever
      // ran on a real install.
      expect(
        keptLines.where((line) => line.contains('merged 1 duplicate')),
        isNotEmpty,
      );
      // The exact list, which also says nothing else was kept.
      expect(keptLevels, [KeptLevel.caught]);
    },
  );
}
