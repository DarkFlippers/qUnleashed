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
    // Tested like [id] and [name] above, not cast. It was
    // `json['lastConnectedAt'] as String? ?? ''`, which answers null for an
    // absent field and **throws** for a present one of the wrong type - so a
    // single entry carrying `"lastConnectedAt": 5` did not cost that entry,
    // it threw a `TypeError` out of `_load`'s parse loop and cost the whole
    // store, reported as `load failed` with no count and no retry. That is
    // the opposite of what every other line on this path is built for, and
    // ADR 0005 is the rule it broke: read entry by entry, and name what was
    // skipped.
    //
    // Both readings of absence stay as they were: a missing field and an
    // unparseable string are the same null answer, which `_load` counts as
    // unreadable. #466
    final storedAt = json['lastConnectedAt'];
    if (storedAt is! String) return null;
    final lastConnectedAt = DateTime.tryParse(storedAt);
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
  /// ran. One site writes it now, [_replace], and it writes
  /// `growable: false` - [debugReset] goes through it too, so that is by
  /// construction rather than by everyone remembering.
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
    _replace(const []);
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
      // Silent, and not a degradation: a store nobody has written yet is the
      // ordinary first launch. The branch after it ends with the same empty
      // list and is nothing like it, which is what #466 was about.
      if (raw == null) {
        _replace(const []);
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        // **The largest loss on this path, and the only silent one.** No entry
        // survives, so the picker's list is empty and [lastDevice] is null -
        // which takes the Bluetooth auto-connect with it, that being its
        // target - and the first [remember] afterwards writes the emptiness
        // over the stored array for good. Not because it is larger than the
        // three drops below - each of those is unbounded too, and the
        // unreadable one reaches this same end state when no entry in the
        // store can be read. What is different is that it is *always* the
        // whole store, where they are sometimes, and that it was the one on
        // this path that said nothing in any build.
        //
        // What arrives here is valid JSON that is not an array: a restored
        // backup, a hand-edited prefs file, or a `{"v":2,"devices":[...]}`
        // from a future build - the same forward-compatible inputs the cap's
        // comment below goes to some length to stay lossless for. Which of
        // those it was is the thing a reader needs and the thing a count
        // cannot carry, so the shape is named and the value never is: an
        // entry holds a Bluetooth address.
        //
        // `caught` rather than the `warn` the `catch` uses, although both can
        // lose the same everything. The split is exception against data: a
        // throw is a fault, where this is a file this method could read and
        // declined to trust - the same judgement, and so the same level, as
        // the three drops below. #466
        LogService.caught(
          '[KnownDevices] discarded the whole stored list: expected a JSON '
          'array, got ${_jsonShape(decoded)}',
        );
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
    } catch (e, st) {
      // With the stack, for the reason [_persist] gives further down the same
      // class. This `try` runs from `SharedPreferences.getInstance()` to the
      // end of the cap report above, and the message alone does not say which
      // of the three faults that can reach here ran:
      //
      //  * a `PlatformException` out of the platform channel;
      //  * a `TypeError` out of `getString`, which is
      //    `_preferenceCache[key] as String?` - a cast and not a checked read,
      //    so a key holding anything but a string throws instead of answering
      //    null. `prefs_reader.dart`'s doc is where this project writes that
      //    down, and the inputs it names there are the ones the
      //    `decoded is! List` branch above is for: an older build that wrote
      //    the key differently, a platform-side migration, an edited plist.
      //    It ends here rather than in a branch of its own because there is no
      //    list to read either way - what the branch above has and this does
      //    not is a shape worth naming;
      //  * a `FormatException` out of [jsonDecode].
      //
      // None of the three names itself, and a `PlatformException` arrives with
      // none of that in its message.
      //
      // Three, and not the three #466 counted. A `TypeError` out of the parse
      // loop was on its list and is now [KnownDevice.fromJson]'s business,
      // where it costs one entry instead of the store. The fourth it counted
      // was a listener throwing out of [notifyListeners] - where the load had
      // in fact succeeded and `_devices` was written, so this line would have
      // been false - and that one was never reachable:
      // `ChangeNotifier.notifyListeners` wraps each listener and routes a
      // throw to `FlutterError.reportError`, so nothing comes back out of it.
      // [notifyListeners] moved below the `try` anyway, which costs one
      // `return` and makes the scope this comment claims true by construction
      // rather than by an argument about another library's internals.
      //
      // `warn` and not [LogService.error], which is the level [_persist] uses:
      // a write that fails loses what the user just did, where a read that
      // fails loses the order of a list they can rebuild by connecting. Once
      // per process either way - [load] memoises, so a store that failed to
      // load stays failed, and empty, for the life of the app with nothing
      // retrying. That is the half of #466 left standing, and it is why this
      // line has to carry enough to act on the first time.
      LogService.warn(
        '[KnownDevices] load failed: ${LogService.describe(e, st)}',
      );
      return;
    }
    notifyListeners();
  }

  /// Names [decoded]'s JSON shape, for the one line that reports a stored list
  /// this class would not read.
  ///
  /// Not `runtimeType`: `jsonDecode` answers with private classes - a parsed
  /// object is `_Map<String, dynamic>` or `_JsonMap` depending on which path
  /// inside `dart:convert` ran - so the type name is noise to a reader and not
  /// something a case can assert on. The arms cover every JSON shape but the
  /// array, which the `is! List` above has already taken; the default is for
  /// the day that stops being true.
  static String _jsonShape(Object? decoded) => switch (decoded) {
    null => 'null',
    Map() => 'an object',
    String() => 'a string',
    num() => 'a number',
    bool() => 'a boolean',
    _ => '${decoded.runtimeType}',
  };

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
  ({int merged, int capped}) _replace(List<KnownDevice> next) {
    final byId = <String, KnownDevice>{};
    for (final device in next) {
      byId.putIfAbsent(device.id, () => device);
    }
    _devices = byId.values.take(_maxEntries).toList(growable: false);
    return (
      merged: next.length - byId.length,
      capped: byId.length - _devices.length,
    );
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
