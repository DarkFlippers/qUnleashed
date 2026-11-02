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
  /// `device.id` reaches here today. What a raw comparison would cost if one
  /// did is worth the line: [remember] builds its new entry through the
  /// canonicalising constructor but drops the old one by *this* test, so a
  /// miss leaves both, and the store holds the same Flipper twice. That is
  /// #444's symptom reintroduced by this file instead of by the plugin, and
  /// [newestPerDevice] would not catch it - it runs on load, not on write.
  ///
  /// The fold is idempotent, so agreeing costs nothing.
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
  /// only reads, and the four assignment sites disagreed about growability,
  /// so what a caller *could* do depended on which path last ran.
  ///
  /// A view rather than the `List.unmodifiable` copy this codebase uses
  /// elsewhere, because this getter is read on every `LinkService.entries`
  /// rebuild - a 24-byte wrapper there, against copying up to
  /// [_maxEntries] elements each time. Only a view stops `[]=` anyway; a
  /// non-growable list does not.
  List<KnownDevice> get devices => UnmodifiableListView(_devices);

  KnownDevice? get lastDevice => _devices.isEmpty ? null : _devices.first;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
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
        // `caught` rather than `warn`: degraded, not broken, and it cannot
        // repeat - [load] memoises, so there is one load per session. The
        // count only, never the id, which is a Bluetooth address.
        LogService.caught(
          '[KnownDevices] dropped $unreadable of ${decoded.length} stored '
          'entries: id, name or lastConnectedAt unreadable',
        );
      }
      _devices = newestPerDevice(parsed);
      notifyListeners();
    } catch (e) {
      LogService.warn('[KnownDevices] load failed: $e');
    }
  }

  /// [parsed] sorted newest first, with one entry per device.
  ///
  /// Split out of [_load] to be reachable without spending the one load a
  /// process gets: [load] memoises on `_loading`, and
  /// `known_devices_persist_test.dart` spends its load on an empty store in
  /// `setUp`. The load path itself is covered once, from its own file -
  /// `known_devices_migration_test.dart` - because a fresh file gets a fresh
  /// memo. Reaching it twice is what is impossible, not reaching it.
  ///
  /// The collapse is not tidiness. Canonicalising on construction can make
  /// two entries that were distinct as stored equal in memory. No released
  /// build can have written that pair - the plugin bump and this constructor
  /// ship together, and within one 2.x build a device has exactly one
  /// spelling per platform - but a round trip gets there: an install that
  /// rolls back to a build on universal_ble 2.x re-remembers the device in the
  /// platform's own case beside the canonical entry, and both fold to the same
  /// id when it comes forward again. A restored or hand-edited store does too.
  /// One Flipper listed twice is what this prevents.
  @visibleForTesting
  static List<KnownDevice> newestPerDevice(List<KnownDevice> parsed) {
    final byNewest = [...parsed]
      ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
    final byId = <String, KnownDevice>{};
    for (final device in byNewest) {
      byId[device.id] ??= device;
    }
    final merged = byNewest.length - byId.length;
    if (merged > 0) {
      // Kept because of what it is, not what it proves: the only place this
      // app drops a remembered device without the user asking, durable at the
      // next mutation. That is the same test `_persist` applies to pick its
      // own level.
      //
      // It says nothing about the ordinary upgrade, and an earlier version of
      // this comment claimed otherwise. A store written by one build on
      // universal_ble 2.x holds one spelling per device, so the fold rewrites
      // it and nothing collides. What reaches here is a store holding *two*
      // spellings of one device - a rollback round trip, or a restored or
      // hand-edited file - which is to say an install that did not need the
      // migration in the first place.
      LogService.caught(
        '[KnownDevices] merged $merged duplicate entries after the id '
        'migration',
      );
    }
    return byId.values.toList(growable: false);
  }

  Future<void> remember(FlipperDevice device) async {
    if (!device.isBle) return;
    await load();
    final entry = KnownDevice.fromDevice(device, DateTime.now());
    _devices = [
      entry,
      ..._devices.where((known) => !known.matches(device)),
    ].take(_maxEntries).toList();
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
    _devices = next;
    notifyListeners();
    await _persist();
  }

  Future<void> forget(KnownDevice device) async {
    await load();
    final next = _devices.where((known) => known.id != device.id).toList();
    if (next.length == _devices.length) return;
    _devices = next;
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
