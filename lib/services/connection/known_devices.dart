import 'dart:convert';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KnownDevice {
  const KnownDevice({
    required this.id,
    required this.name,
    required this.lastConnectedAt,
  });

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
      parsed.sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
      _devices = parsed;
      notifyListeners();
    } catch (e) {
      LogService.log('[KnownDevices] load failed: $e');
    }
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

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final device in _devices) device.toJson()]),
      );
    } catch (e) {
      LogService.log('[KnownDevices] save failed: $e');
    }
  }
}
