import 'dart:collection';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';

class KnownDevice {
  /// Canonicalises [id] rather than storing what it was handed, which is the
  /// migration for every entry a 2.x build wrote.
  ///
  /// `known_devices_v1` written by any build before this one holds an
  /// upper-case id - a MAC on Android and Linux, Apple's upper-case
  /// `uuidString` on iOS and macOS - because that is what universal_ble 2.x
  /// reported. Windows is the exception; it was already lower-case. From
  /// 3.0.0 the plugin reports lower-case on every platform this app ships, so
  /// a stored id compares unequal to the live one for the same Flipper and
  /// [matches] fails. What that costs, in the order a user would meet it:
  ///
  ///  * a scan that hears the Flipper never marks its row, because
  ///    `LinkService._onHeard` returns early unless a known entry matches - so
  ///    the remembered row sits there looking out of range;
  ///  * the auto-connect reaches it (flipperlib canonicalises the address it
  ///    is handed) and then cannot recognise the session as belonging to that
  ///    row, which is keyed `'ble:${known.id}'`, so the row reads disconnected
  ///    while the link is up;
  ///  * [remember] then adds the live spelling *beside* the stored one, so the
  ///    list shows one Flipper twice under the same name - and [forget]
  ///    removes exactly the row that was tapped, leaving its identical twin,
  ///    which reads as having done nothing.
  ///
  /// On construction, so that there is one point to enforce it and no second
  /// spelling in the store to reason about.
  ///
  /// And that is why there is no `known_devices_v2`: an entry read through
  /// [fromJson] is canonical in memory immediately and written back canonical
  /// by the next mutation. A build that rolls back is then left with a
  /// lower-case id, and 2.x does **not** take either case - it passes the id
  /// to the platform verbatim, and Android's `getRemoteDevice` rejects a
  /// lower-case MAC outright while the Linux backend matches BlueZ's
  /// upper-case address with `==`. What that costs is one failed auto-connect:
  /// the next connect from the picker re-remembers the device in the
  /// platform's own case. Not worth a second schema. #444
  KnownDevice({
    required String id,
    required this.name,
    required this.lastConnectedAt,
  }) : id = canonicalBleDeviceId(id);

  final String id;
  final String name;
  final DateTime lastConnectedAt;

  factory KnownDevice.fromDevice(FlipperDevice device, DateTime when) {
    return KnownDevice(id: device.id, name: device.name, lastConnectedAt: when);
  }

  /// Canonicalises what it is handed, so that it agrees with the
  /// constructor whatever the caller holds.
  ///
  /// Defence across a submodule boundary rather than a live fix: flipperlib
  /// folds every BLE id it produces - `BleDiscoveredDevice` on construction,
  /// and `connectBleAddress` for an id a caller supplies - so no uncanonical
  /// `device.id` reaches here today. The fold is idempotent, so agreeing
  /// costs nothing.
  ///
  /// What a miss would cost is no longer a duplicate entry. [remember] used
  /// to drop the old entry by *this* test, so a miss left both and the store
  /// held one Flipper twice - #444's symptom reintroduced by this file rather
  /// than by the plugin. Since #456 every write goes through [_replace],
  /// which folds on `id`, so that outcome is unreachable from here. The two
  /// callers left are [updateName], where a miss silently declines a rename,
  /// and `LinkService._onHeard`, where it leaves a remembered row unmarked
  /// while the scan can hear it.
  bool matches(FlipperDevice device) =>
      device.isBle && canonicalBleDeviceId(device.id) == id;

  static KnownDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final lastConnectedAt = DateTime.tryParse(
      json['lastConnectedAt'] as String? ?? '',
    );
    if (lastConnectedAt == null) return null;
    return KnownDevice(id: id, name: name, lastConnectedAt: lastConnectedAt);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lastConnectedAt': lastConnectedAt.toIso8601String(),
  };
}

/// Persistent registry of BLE devices the app has successfully connected to,
/// newest first. USB never lands here: a plugged-in Flipper auto-connects on
/// its own, while a BLE bond is worth remembering across sessions. The devices
/// page renders the list under the Search action and the newest entry is the
/// auto-connect target.
class KnownDevicesStore extends ChangeNotifier {
  KnownDevicesStore._();

  static final KnownDevicesStore instance = KnownDevicesStore._();

  static const String _prefsKey = 'known_devices_v1';
  static const int _maxEntries = 8;

  /// A plain field again. It was a getter over `_devicesValue` with a setter
  /// that fed every name to `Scrub.rememberDeviceName`, because this is the
  /// only place that knows a Flipper's name *before* a session exists. ADR
  /// 0013 §6.2 no longer redacts device names, so there is nothing to feed.
  List<KnownDevice> _devices = const [];

  Future<void>? _loading;

  /// Not the list itself: a [ChangeNotifier] that hands out its own mutable
  /// state has no way to notify about a write it did not make. Every caller
  /// only reads, and before [_replace] the assignment sites disagreed about
  /// growability, so what a caller *could* do depended on which path last
  /// ran. One production site writes it now - [_replace] - and it writes
  /// `growable: false`; the other writer is [debugReset], with `const []`.
  ///
  /// A view rather than the `List.unmodifiable` copy this codebase uses
  /// elsewhere, because this getter is read on every `LinkService.entries`
  /// rebuild - a 24-byte wrapper there, against copying up to
  /// [_maxEntries] elements each time. Only a view stops `[]=` anyway; a
  /// non-growable list does not.
  List<KnownDevice> get devices => UnmodifiableListView(_devices);

  KnownDevice? get lastDevice => _devices.isEmpty ? null : _devices.first;

  Future<void> load() => _loading ??= _load();

  /// Rewinds `_loading` and `_devices`, so that a case gets a real [_load]
  /// against its own `SharedPreferences` fixture.
  ///
  /// Those two fields and nothing else - in particular the [ChangeNotifier]'s
  /// listeners are the caller's to remove, and `addTearDown(service.dispose)`
  /// is how `link_autoconnect_test.dart` does it. An in-flight [_load] is not
  /// cancelled either: nulling `_loading` does not stop one already past its
  /// first `await` from assigning `_devices` in the next case. Reachable in
  /// principle, since `LinkService.start` does not await its load; closing it
  /// would need a generation counter, which is more machinery than the
  /// exposure justifies. #456 widened it from one assignment site to three -
  /// [_load]'s two early returns write `const []` through [_replace] now, so a
  /// stale load that used to return having touched nothing can empty what the
  /// current case loaded.
  ///
  /// Wired once in `test/flutter_test_config.dart` rather than called by the
  /// files that need it, which is the rule that file's own header states: a
  /// reset kept by hand in N files is the one that goes stale when somebody
  /// adds the N+1th. Before this, [load] memoising on `_loading` with nothing
  /// clearing it meant a process got exactly one real load - so a claim about
  /// the load path needed a file of its own to get a fresh memo, and two
  /// files held one case each for that reason alone, while six more cleared
  /// the store by hand across seven sites. #452
  ///
  /// Deliberately silent: it does not [notifyListeners]. Firing one would fan
  /// out into whatever `LinkService` is still attached from a case that has
  /// finished, which is the leak this is cleaning up after rather than an
  /// audience. Nothing caches the list - every consumer reads `devices` or
  /// `lastDevice` live - so a listener that is not told cannot render a stale
  /// one; it reads `[]` the next time it reads at all.
  @visibleForTesting
  void debugReset() {
    _loading = null;
    _devices = const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      // Through [_replace] like every other exit that read the store, so
      // that "a load that got as far as reading has written `_devices`" holds
      // without a reader checking which branch ran. The `catch` at the end is
      // the one exit outside that: it writes nothing, which is only harmless
      // because the field starts and resets to `const []`.
      //
      // Silent, and in the first case not even a degradation: a store nobody
      // has written yet is the ordinary first launch. The second case is a
      // degradation and the silence there is not defended - it is older than
      // this method's rewrite and wants its own fix.
      if (raw == null) {
        _replace(const []);
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _replace(const []);
        return;
      }
      final parsed = <KnownDevice>[];
      var unreadable = 0;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          unreadable++;
          continue;
        }
        // Not a loss. `toJson` has never written a `link` field, so this skip
        // is defensive against a shape that was never stored.
        if (item['link'] == 'usb') continue;
        final device = KnownDevice.fromJson(item);
        if (device == null) {
          unreadable++;
          continue;
        }
        parsed.add(device);
      }
      if (unreadable > 0) {
        // Kept, because the drop is durable: the next mutation writes
        // `_devices` back over the whole array, so an entry that could not be
        // read here is gone from the store. [KnownDevice.fromJson] answering
        // null is also what the id migration passes through, so a silent drop
        // is this fix visibly not applying - and what the user sees is a
        // Flipper they paired simply absent from the list, with the
        // auto-connect target possibly naming a different one.
        //
        // `caught` rather than `warn`: degraded, not broken. Once per
        // launch, not once per session only - [load] memoises, so it cannot
        // repeat while the app runs, but nothing writes the surviving list
        // back here, so an unreadable entry is read and reported again at
        // every launch until the user connects, renames or forgets
        // something. The count only, never the id, which is a Bluetooth
        // address.
        LogService.caught(
          '[KnownDevices] dropped $unreadable of ${decoded.length} stored '
          'entries: id, name or lastConnectedAt unreadable',
        );
      }
      final (:merged, :capped) = _replace(_newestFirst(parsed));
      if (merged > 0) {
        // Kept because of what it is, not what it proves: a remembered device
        // dropped without the user asking, durable at the next mutation. That
        // is the same test `_persist` applies to pick its own level.
        //
        // It says nothing about the ordinary upgrade, and an earlier version
        // of this comment claimed otherwise. A store written by one build on
        // universal_ble 2.x holds one spelling per device, so the fold
        // rewrites it and nothing collides. What reaches here is a store
        // holding *two* spellings of one device - a rollback round trip, or a
        // restored or hand-edited file - which is to say an install that did
        // not need the migration in the first place.
        LogService.caught(
          '[KnownDevices] merged $merged duplicate entries after the id '
          'migration',
        );
      }
      if (capped > 0) {
        // Kept for the same reason, by the same test: durable, and the user
        // asked for nothing. The next mutation writes `_devices` back over
        // the whole stored array, so what is cut here is gone from disk at
        // the first [remember].
        //
        // [remember]'s own trim is silent and is not the precedent, because
        // there the user tapped connect on a ninth Flipper and displaced one
        // entry they chose. Nobody tapped anything here and the count is
        // unbounded - a restored twenty-entry store loses twelve.
        // [_maxEntries] is private, so no user has been told there is a cap:
        // from their side this is indistinguishable from the unreadable drop,
        // and without this line it is also indistinguishable from a store
        // that never loaded.
        //
        // Once per launch rather than once ever, as with the unreadable drop
        // above and for the same reason: nothing here writes the trim back, so
        // an over-cap store stays over-cap on disk until the user connects,
        // renames or forgets something. That is deliberate - "a store a future build with a
        // larger cap wrote" is one of the inputs - and persisting the trim
        // would destroy entries that build can still read. Lossless until a
        // mutation is the forward-compatible answer, and the repeat is its
        // price.
        //
        // `parsed.length - merged` is the count [_replace] was handed after
        // the fold, which is the total this drop is out of.
        LogService.caught(
          '[KnownDevices] dropped $capped of ${parsed.length - merged} '
          'remembered devices over the cap of $_maxEntries, oldest first',
        );
      }
      notifyListeners();
    } catch (e) {
      LogService.warn('[KnownDevices] load failed: $e');
    }
  }

  /// [parsed] sorted newest first, which is the order [_replace] then keeps.
  ///
  /// Sorting lives here rather than in [_replace] because [_load] is the only
  /// path handed entries in arbitrary order: [remember] prepends to an
  /// already-ordered list, and [updateName] and [forget] rebuild one from
  /// one. That split is what lets [_replace] be order-preserving, which #453
  /// established it has to be.
  static List<KnownDevice> _newestFirst(List<KnownDevice> parsed) =>
      [...parsed]
        ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));

  /// Writes [next] into `_devices` - one entry per device, no more than
  /// [_maxEntries] of them - and reports what it dropped getting there.
  ///
  /// The one assignment every production path goes through. There were four,
  /// and two of them capped. The other two, [updateName] and [forget], were
  /// correct only because their input had been capped by whichever path ran
  /// before them - an induction that nothing enforced and nothing wrote down.
  /// #453 was the second time the cap was found missing from an assignment
  /// site, and a fifth writer would have looked exactly like [updateName] did
  /// then. #456
  ///
  /// **Order-preserving, and that is load-bearing.** The caller fixes the
  /// order; on a collision the earlier entry wins. That is why [remember]
  /// puts its new entry first and why [_load] sorts before calling. Sorting
  /// here instead would be the bug #453 named when it deferred this: against
  /// a skewed clock, or a stored entry carrying a future timestamp, a sort
  /// would let a stale entry win [lastDevice] and so become the auto-connect
  /// target.
  ///
  /// Returns the counts instead of logging them, because whether a drop is
  /// worth a line is the caller's to know. The same drop is a
  /// [LogService.caught] in [_load], where the user asked for nothing, and
  /// silent in [remember], where they tapped connect on a ninth Flipper.
  ({int merged, int capped}) _replace(Iterable<KnownDevice> next) {
    final byId = <String, KnownDevice>{};
    var seen = 0;
    for (final device in next) {
      seen++;
      byId.putIfAbsent(device.id, () => device);
    }
    _devices = byId.values.take(_maxEntries).toList(growable: false);
    return (merged: seen - byId.length, capped: byId.length - _devices.length);
  }

  Future<void> remember(FlipperDevice device) async {
    if (!device.isBle) return;
    await load();
    final entry = KnownDevice.fromDevice(device, DateTime.now());
    // `entry` first plus first-wins folding is exactly what
    // `where((known) => !known.matches(device))` was. This method has already
    // returned unless `device.isBle`, and `entry.id` is
    // `canonicalBleDeviceId(device.id)` because the constructor folds, so
    // `known.matches(device)` reduces to `known.id == entry.id`. What goes
    // with it is the second spelling of one invariant - [KnownDevice.matches]
    // on write, id-keyed folding on load - which is the divergence that
    // method's own doc flags as the hazard. #456
    //
    // Both counts discarded on purpose. A merge is the ordinary reconnect -
    // `entry` is a second spelling of a device `_devices` already holds, and
    // folding it away is the whole of what this call does, which
    // `known_devices_persist_test.dart`'s write-over case is about. There is
    // nothing to report: the entry it displaced is the same Flipper, one
    // moment older. A cap is silent for a different reason - the user tapped
    // connect on a ninth Flipper and displaced one they chose.
    _replace([entry, ..._devices]);
    notifyListeners();
    await _persist();
  }

  Future<void> updateName(FlipperDevice device, String name) async {
    if (!device.isBle) return;
    await load();
    var changed = false;
    final next = <KnownDevice>[];
    for (final known in _devices) {
      if (known.matches(device) && known.name != name) {
        changed = true;
        next.add(
          KnownDevice(
            id: known.id,
            name: name,
            lastConnectedAt: known.lastConnectedAt,
          ),
        );
      } else {
        next.add(known);
      }
    }
    if (!changed) return;
    // One for one, so neither count can be non-zero; through [_replace] so
    // that it stays true by construction rather than by that argument.
    _replace(next);
    notifyListeners();
    await _persist();
  }

  Future<void> forget(KnownDevice device) async {
    await load();
    final next = _devices.where((known) => known.id != device.id).toList();
    if (next.length == _devices.length) return;
    // Only ever shorter, so as with [updateName] both counts are zero - and
    // as there, through [_replace] so that nothing has to argue it.
    _replace(next);
    notifyListeners();
    await _persist();
  }

  /// Not `persistSetting`, which logs at warn: the ruling below is error,
  /// and this is a device list rather than a setting. What it shares is the
  /// half #313 was about - `setString` answering `false` without throwing.
  ///
  /// The two bodies say the same thing as that function's, deliberately: a
  /// reader grepping for one failure should not have to know there are two
  /// spellings of it.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accepted = await prefs.setString(
        _prefsKey,
        jsonEncode([for (final device in _devices) device.toJson()]),
      );
      if (!accepted) {
        LogService.error(
          '[KnownDevices] save failed: the store refused the write',
        );
      }
    } catch (e, st) {
      // error, not warn, alone in this sweep: it is the only failure here
      // that loses something durable. notifyListeners has already run, so the
      // picker shows the device as remembered and the user finds out at the
      // next launch, when it is gone. Worth having in a log kept at
      // QLOG_LEVEL=error, and it cannot repeat - one write per mutation.
      //
      // With the stack, which is the only thing naming which mutation was
      // saving - remember, updateName or forget. A PlatformException arrives
      // with none of that in its message.
      LogService.error(
        '[KnownDevices] save failed: ${LogService.describe(e, st)}',
      );
    }
  }
}
