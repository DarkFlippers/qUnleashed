import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';

class KnownDevice {
  /// Canonicalises [id] rather than storing what it was handed, which is the
  /// migration for every entry a 2.x build wrote.
  ///
  /// `known_devices_v1` on an Android install from before universal_ble 3.0.0
  /// holds upper-case MACs, because that is what the plugin reported then.
  /// From 3.0.0 it reports lower-case everywhere, so a stored id compares
  /// unequal to the live one for the same Flipper: [matches] fails, the
  /// devices page lists the remembered entry and the Flipper in front of the
  /// user as two devices, [forget] takes the one that is not there, and the
  /// auto-connect target is an id no callback will ever equal.
  ///
  /// On construction, so that there is one point to enforce it and no second
  /// spelling in the store to reason about. That is also why there is no
  /// `known_devices_v2`: an entry read through [fromJson] is canonical in
  /// memory immediately and written back canonical by the next mutation, and
  /// a build that rolls back reads a lower-case id it can still connect with
  /// - universal_ble 2.x accepted either case as input too. #444
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

  bool matches(FlipperDevice device) => device.isBle && device.id == id;

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

  List<KnownDevice> get devices => _devices;

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
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        if (item['link'] == 'usb') continue;
        final device = KnownDevice.fromJson(item);
        if (device != null) parsed.add(device);
      }
      _devices = newestPerDevice(parsed);
      notifyListeners();
    } catch (e) {
      LogService.warn('[KnownDevices] load failed: $e');
    }
  }

  /// [parsed] newest first, with one entry per device.
  ///
  /// Split out of [_load] to be reachable: the store is a singleton whose
  /// [load] memoises, so a test cannot put a file in front of it twice.
  ///
  /// The collapse is not tidiness. Canonicalising on construction can make
  /// two entries that were distinct as stored equal in memory, which is a
  /// shape an install that ran a 2.x build and a 3.x build of the same device
  /// can be in. One Flipper listed twice is what this prevents.
  @visibleForTesting
  static List<KnownDevice> newestPerDevice(List<KnownDevice> parsed) {
    final byNewest = [...parsed]
      ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
    final byId = <String, KnownDevice>{};
    for (final device in byNewest) {
      byId.putIfAbsent(device.id, () => device);
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
