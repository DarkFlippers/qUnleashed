// Every claim about what `KnownDevicesStore._load` makes of a stored
// `known_devices_v1`, from the file on disk.
//
// Not every claim about the load path: `link_autoconnect_test.dart`'s 'is
// dialled by the canonical id' drives `_load` from disk too, deliberately,
// because what it is about is the far end of the chain.
//
// One file holding every claim about it, which is new. Until #452 these were
// two files holding one case each, because `load()` memoised on `_loading`
// with nothing clearing it: a process got exactly one real load, so a case
// that needed its own store in front of it needed its own isolate to get a
// fresh memo. `test/flutter_test_config.dart` now resets the store before
// every case, so the load path is reachable as often as it is interesting -
// and the collapse no longer has to be a `@visibleForTesting static` to be
// tested at all.
//
// Each case therefore seeds `SharedPreferences` and asserts on `devices`,
// which is the behaviour, rather than on a helper lifted out of the body.
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

  /// Puts [raw] on disk verbatim and performs the load the case is about.
  ///
  /// [loadFrom] cannot reach these: it encodes a `List`, so the one thing it
  /// can never seed is a store that is not an array - which is the input #466
  /// was about, and the input a future `{"v":2,...}` schema has.
  Future<KnownDevicesStore> loadRaw(String raw) async {
    SharedPreferences.setMockInitialValues({'known_devices_v1': raw});
    await KnownDevicesStore.instance.load();
    return KnownDevicesStore.instance;
  }

  /// Puts [entries] on disk as the stored array and performs the load the
  /// case is about.
  ///
  /// Once per case, not once per process - which is the trap moving rather
  /// than closing. A second call inside one body silently serves the first
  /// fixture, because `load()` still memoises; what the reset buys is a fresh
  /// memo per case. `KnownDevicesStore.debugReset()` by hand is how a case
  /// loads twice on purpose.
  ///
  /// [Object] rather than a map, because an element that is not a map at all
  /// is one of the four ways `_load` loses an entry.
  Future<KnownDevicesStore> loadFrom(List<Object> entries) =>
      loadRaw(jsonEncode(entries));

  // Two spellings of one Flipper, which is the shape a round trip leaves: a
  // store this build canonicalised, a rollback to one on universal_ble 2.x
  // that re-remembers the device in the platform's own case beside it, and
  // then this build again. No released build wrote that pair - the plugin
  // bump and the fold ship together - and a restored or hand-edited store
  // gets there too.
  //
  // Measured, with `_replace`'s body replaced by
  // `_devices = next.take(_maxEntries)` and zero counts - the fold gone, the
  // sort and the cap kept. Three cases fail: this one,
  // `known_devices_persist_test.dart`'s 'is written over, not beside' - the
  // fold is the whole of what `remember` does about a duplicate, so the read
  // side and the write side go together - and the cap case below, which loses
  // its `caught` line because the counts are computed from the fold and go
  // with it.
  //
  // The recipe is the claim. A mutation that drops the fold *and* flattens
  // the counts is not the same as one that drops the fold alone, and the
  // third failure is the difference; #444's note gave a third recipe again,
  // `parsed.sort(); _devices = parsed;`, which drops the cap as well. #444.
  test(
    'a store written by a 2.x build loads as one canonical device',
    () async {
      final known = await loadFrom([
        storedEntry(storedById, 'the older name', '2026-10-01T10:00:00.000'),
        storedEntry(reportedById, 'the newer name', '2026-10-02T10:00:00.000'),
      ]);

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

  test('without collapsing two devices into one', () async {
    // The other half of the collapse: it is per id, not a `take(1)`. Newest
    // first, which is what `lastDevice` reads as the auto-connect target.
    //
    // This was a direct call to `newestPerDevice` in
    // `known_devices_persist_test.dart` - the helper was public for it.
    // Through the store instead, so what is pinned is the store's answer.
    final known = await loadFrom([
      storedEntry(reportedById, 'older', '2026-10-01T10:00:00.000'),
      storedEntry(otherById, 'newer', '2026-10-02T10:00:00.000'),
    ]);

    expect(known.devices.map((d) => d.name), ['newer', 'older']);
    expect(keptLevels, isEmpty, reason: 'nothing was dropped or merged');
  });

  // Why the line matters rather than the drop: `_load` reads entry by entry
  // and the next mutation writes `_devices` back over the whole stored array,
  // so an entry that could not be read here is gone from the store for good.
  // The user sees a Flipper they paired simply absent from the list - and
  // since `KnownDevice.fromJson` answering null is also what the id migration
  // passes through, a silent drop is the migration visibly not applying.
  // ADR 0005 is the rule it follows: read entry by entry, and name what was
  // skipped.
  test(
    'an entry the migration cannot read is counted, not swallowed',
    () async {
      final known = await loadFrom([
        storedEntry(storedById, 'Flipper Zoe', '2026-10-01T10:00:00.000'),
        // Every way an entry is lost here, which is four: three shapes
        // `fromJson` answers null for - a field of the wrong type, a
        // timestamp that will not parse, and a timestamp of the wrong type -
        // and one that never reaches it, an element that is not a map.
        {
          'id': 12345,
          'name': 'nope',
          'lastConnectedAt': '2026-10-01T10:00:00.000',
        },
        {'id': otherById, 'name': 'no date'},
        // **The one that used to cost the whole store.** `fromJson` read this
        // field with `as String? ?? ''`, which throws on a present field of
        // the wrong type rather than answering null, so the `TypeError` left
        // the parse loop, left `_load`, and landed in the catch as
        // `load failed` - no entry kept, no count, and nothing retrying for
        // the life of the process. One entry of five, now, like its three
        // neighbours. #466
        {'id': otherById, 'name': 'numeric date', 'lastConnectedAt': 5},
        'not a map',
      ]);

      // The one readable entry survives, canonicalised.
      expect(known.devices.map((d) => d.id), [reportedById]);

      // And the four that did not are named. The count, never the ids - those
      // are Bluetooth addresses.
      expect(
        keptLines.where(
          (line) => line.contains('dropped 4 of 5 stored entries'),
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

  test('a store over the cap loads capped, oldest first to go', () async {
    // #453: the cap was applied in `remember` and in none of the other three
    // assignments, so an oversized store loaded whole and stayed that way -
    // `updateName` rebuilds one-for-one and `forget` only shrinks, so nothing
    // trimmed it until the next `remember`.
    //
    // Ten entries, newest last in the stored array so that the case also
    // pins that the sort happens before the cut rather than after. A store
    // this size is not one this app wrote: `remember` is the only path that
    // grows the list and it caps. What reaches here is a restored or
    // hand-edited file, a store a future build with a larger cap wrote, or a
    // backup that merged two devices' files.
    final known = await loadFrom([
      for (var i = 0; i < 10; i++)
        storedEntry(
          '80:e1:27:00:00:0$i',
          'Flipper $i',
          '2026-10-${(i + 1).toString().padLeft(2, '0')}T10:00:00.000',
        ),
    ]);

    expect(known.devices, hasLength(8));
    // The eight newest, newest first. The two dropped are the two oldest,
    // which is what `remember` drops when it trims.
    expect(known.devices.map((d) => d.name), [
      'Flipper 9',
      'Flipper 8',
      'Flipper 7',
      'Flipper 6',
      'Flipper 5',
      'Flipper 4',
      'Flipper 3',
      'Flipper 2',
    ]);

    // And it says so, for the same reason the other two drops in `_load` do:
    // something the user paired went missing for a reason they cannot see.
    // The first draft of this made the cap silent, reasoning that `remember`
    // trims to the same eight without a word - but there the user tapped
    // connect on a ninth Flipper and displaced one entry they chose, and here
    // nobody asked and twelve can go. `caught_budget_test.dart`'s own charter
    // for the two existing lines is "a remembered device being thrown away
    // where the user asked for nothing", which this is verbatim.
    //
    // The count is the point: without it, "only eight of my Flippers are
    // there" cannot be told from a store that never loaded.
    expect(
      keptLines.where(
        (line) => line.contains('dropped 2 of 10 remembered devices'),
      ),
      isNotEmpty,
    );
    expect(keptLevels, [KeptLevel.caught]);
  });

  // What #466 was filed for: a store that is valid JSON and not an array.
  //
  // Both halves of the old behaviour are claimed here - the list is emptied,
  // and until #466 that happened in silence. It is the largest loss on this
  // path and was the only unreported one: no entry survives, so the picker is
  // empty and `lastDevice` is null, which is the Bluetooth auto-connect's
  // target, and the next `remember` writes the emptiness over the stored
  // array for good.
  //
  // The shapes are the inputs that actually produce it: a `v2` envelope a
  // future build might write, which is the forward-compatible case the cap's
  // own comment is careful about, and two scalars, which is what a truncated
  // or hand-edited prefs file looks like.
  group('a stored list that is not a list', () {
    for (final (raw, shape) in [
      ('{"v":2,"devices":[]}', 'an object'),
      ('"$reportedById"', 'a string'),
      ('null', 'null'),
    ]) {
      test('is emptied and reported, for $shape', () async {
        final known = await loadRaw(raw);

        expect(known.devices, isEmpty);
        expect(known.lastDevice, isNull);

        // The shape, because that is what tells a future schema from a
        // corrupted file, and a count of entries cannot carry it. Named in
        // words rather than by `runtimeType`, which for an object `jsonDecode`
        // answers with a private class name - `_Map<String, dynamic>` here,
        // and that is the shape of the three that matters, a `v2` envelope
        // being the input a future build would write.
        expect(
          keptLines.where(
            (line) =>
                line.contains('discarded the whole stored list') &&
                line.contains('got $shape'),
          ),
          isNotEmpty,
        );
        // The exact list, which also says nothing else was kept. Not that
        // the shape was reported once: `LogService._isNewLine` drops a
        // *consecutive* identical body, so this cannot tell one call from two
        // with the same text - the trap CLAUDE.md's anti-pattern list names.
        expect(keptLevels, [KeptLevel.caught]);
        // Never the value. `"80:e1:27:aa:bb:cc"` is a whole store that decodes
        // to a Bluetooth address, which is the one input here where the
        // difference between naming the shape and naming the value is a
        // difference in what reaches a report.
        expect(
          keptLines.where((line) => line.contains(reportedById)),
          isEmpty,
          reason: 'an address must not reach a kept line',
        );
      });
    }
  });

  // The other exit this method has, and the one that keeps nothing: a store
  // that is not JSON at all. What the case is about is the stack, which is
  // the only thing naming which of two faults ran - a `FormatException` from
  // `jsonDecode` or a `PlatformException` out of the platform channel - since
  // neither names itself and a `PlatformException` arrives with nothing in
  // its message. `_persist`, lower in the same class, has used `describe` all
  // along; this line used a bare `$e` until #466.
  test('a store that is not JSON is reported with its stack', () async {
    final known = await loadRaw('{"v":2,');

    expect(known.devices, isEmpty);

    final failures = keptLines.where((line) => line.contains('load failed'));
    expect(failures, isNotEmpty);
    expect(failures.single, contains('FormatException'));
    // The stack, and this is the assertion that pins it: the trace is the
    // only part of the line naming the method that failed, which is the
    // whole of the change here.
    //
    // An `expect(..., contains('\n'))` stood above this and was dead
    // weight. `describe` does join the error and the trace with a newline,
    // so it read like the claim - but `FormatException.toString()` is
    // itself three lines for a truncated source, the message, the source
    // and a caret, so it holds whether or not a trace was appended.
    // Measured against the `$e` this replaced: the mutation fails on the
    // line below, and that one passed. It is the trap CLAUDE.md lists
    // fourth - a test green on a mechanism other than the one it claims -
    // and reading it did not catch it.
    expect(failures.single, contains('known_devices.dart'));
    // `warn`, not `caught`: an exception is a fault, where a list of the
    // wrong shape is data this method declined to trust.
    expect(keptLevels, [KeptLevel.warning]);
  });

  // The rewind, and then the empty-disk load that follows it in every file
  // that seeds through `SharedPreferences` - which is the path
  // `known_devices_persist_test.dart`'s `setUp` and `serviceWith()` take, and
  // the only case here that takes it.
  //
  // Two acts because they pin different things, and the comment this replaces
  // got that wrong twice. The read *before* any load is what pins
  // `debugReset` emptying `_devices` at all: measured, deleting that leaves
  // the rest of the suite green. The load after it pins nothing on its own -
  // deleting `_replace(const [])` from `_load`'s `raw == null` branch leaves
  // the whole suite green too, because the reset has already emptied the
  // field - and it cannot: [load] memoises, so the only second load in a
  // process follows a reset. That branch assigns for the invariant, which is
  // what its own comment now says rather than claiming a test.
  test(
    'is empty when it is rewound, and stays empty on an empty disk',
    () async {
      await loadFrom([
        storedEntry(reportedById, 'Flipper Zoe', '2026-10-01T10:00:00.000'),
      ]);
      expect(KnownDevicesStore.instance.devices, isNotEmpty, reason: 'premise');

      KnownDevicesStore.instance.debugReset();

      expect(KnownDevicesStore.instance.devices, isEmpty);
      expect(KnownDevicesStore.instance.lastDevice, isNull);

      SharedPreferences.setMockInitialValues(const {});
      await KnownDevicesStore.instance.load();

      expect(KnownDevicesStore.instance.devices, isEmpty);
      expect(KnownDevicesStore.instance.lastDevice, isNull);
    },
  );
}
