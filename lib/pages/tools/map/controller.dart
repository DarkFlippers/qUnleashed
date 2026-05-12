import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../archive/storage.dart';
import '../../archive/models/category.dart';
import 'models/pin.dart';

enum MapLocationStatus { idle, requesting, granted, denied, serviceDisabled, error }

class MapToolController extends ChangeNotifier {
  MapToolController({ArchiveStorage? storage, FlipperClient? client})
      : _storage = storage ?? ArchiveStorage(),
        _client = client ?? FlipperOneClient().get();

  final ArchiveStorage _storage;
  final FlipperClient _client;

  bool _loading = false;
  String? _loadError;
  List<MapPin> _pins = const [];
  MapLocationStatus _locationStatus = MapLocationStatus.idle;
  String? _locationError;
  Position? _userPosition;
  Position? _previousUserPosition;
  double? _userBearingDegrees;
  StreamSubscription<Position>? _posSub;

  bool get loading => _loading;
  String? get loadError => _loadError;
  List<MapPin> get pins => _pins;
  MapLocationStatus get locationStatus => _locationStatus;
  String? get locationError => _locationError;
  Position? get userPosition => _userPosition;
  double? get userBearingDegrees => _userBearingDegrees;
  bool get isFlipperConnected => _client.isConnected;

  Future<void> initialize() async {
    await loadFiles();
    await requestLocation();
  }

  Future<void> loadFiles() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final deviceName = await _storage.readLastDeviceName();
      if (deviceName == null || deviceName.isEmpty) {
        _pins = const [];
        _loadError = 'No synced Flipper found. Connect and sync first in Archive.';
        return;
      }
      final entries = await _storage.listAll(deviceName);
      final out = <MapPin>[];
      for (final entry in entries) {
        final pin = await _parseFile(entry);
        if (pin != null) out.add(pin);
      }
      _pins = out;
    } catch (e) {
      _loadError = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _remotePathFor(LocalKeyEntry entry) {
    final fileName = '${entry.name}.${entry.extension}';
    if (entry.subFolder.isEmpty) return '${entry.category.remoteDir}/$fileName';
    return '${entry.category.remoteDir}/${entry.subFolder}/$fileName';
  }

  Future<MapPin?> _parseFile(LocalKeyEntry entry) async {
    try {
      final normalizedExtension = entry.extension.toLowerCase();
      final file = io.File(entry.path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      double? lat;
      double? lon;
      String? frequency;
      String? protocol;
      String? bit;
      String? uid;
      String? key;
      String? keyType;
      for (final raw in content.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final lower = line.toLowerCase();
        final colon = line.indexOf(':');
        if (colon < 0) continue;
        final value = line.substring(colon + 1).trim();
        if (lower.startsWith('latitude:') || lower.startsWith('latitute:') || lower.startsWith('lat:')) {
          lat = double.tryParse(value);
        } else if (lower.startsWith('longitude:') || lower.startsWith('lon:') || lower.startsWith('lng:')) {
          lon = double.tryParse(value);
        } else if (lower.startsWith('frequency:')) {
          frequency = value;
        } else if (lower.startsWith('protocol:')) {
          protocol = value;
        } else if (lower.startsWith('bit:')) {
          bit = value;
        } else if (lower.startsWith('uid:')) {
          uid = value;
        } else if (lower.startsWith('key:') || lower.startsWith('rom data:')) {
          key = value;
        } else if (lower.startsWith('key type:')) {
          keyType = value;
        }
      }
      if (lat == null || lon == null) return null;
      if (lat == 0 && lon == 0) return null;
      return MapPin(
        id: entry.path,
        name: entry.name,
        path: entry.path,
        fileName: '${entry.name}.${entry.extension}',
        extension: normalizedExtension,
        subFolder: entry.subFolder,
        category: entry.category,
        remotePath: _remotePathFor(entry),
        latitude: lat,
        longitude: lon,
        content: content,
        frequency: frequency,
        protocol: protocol,
        bit: bit,
        uid: uid,
        key: key,
        keyType: keyType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeCoordinates({
    required String localPath,
    String? remotePath,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final file = io.File(localPath);
      if (!await file.exists()) return false;
      final original = await file.readAsString();
      final updated = _patchCoordinates(original, latitude, longitude);
      await file.writeAsString(updated, flush: true);
      if (remotePath != null && remotePath.isNotEmpty && _client.isConnected) {
        try {
          await _client.storageWriteChunked(remotePath, utf8.encode(updated));
        } catch (_) {}
      }
      await loadFiles();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _patchCoordinates(String original, double latitude, double longitude) {
    final latStr = latitude.toStringAsFixed(6);
    final lonStr = longitude.toStringAsFixed(6);
    final lines = original.split('\n');
    final out = <String>[];
    var wroteLat = false;
    var wroteLon = false;
    for (final raw in lines) {
      final colon = raw.indexOf(':');
      if (colon > 0) {
        final key = raw.substring(0, colon).trim().toLowerCase();
        if (key == 'lat' || key == 'latitude' || key == 'latitute') {
          out.add('${raw.substring(0, colon)}: $latStr');
          wroteLat = true;
          continue;
        }
        if (key == 'lon' || key == 'lng' || key == 'longitude') {
          out.add('${raw.substring(0, colon)}: $lonStr');
          wroteLon = true;
          continue;
        }
      }
      out.add(raw);
    }
    if (!wroteLat || !wroteLon) {
      while (out.isNotEmpty && out.last.trim().isEmpty) {
        out.removeLast();
      }
      if (!wroteLat) out.add('Lat: $latStr');
      if (!wroteLon) out.add('Lon: $lonStr');
      out.add('');
    }
    return out.join('\n');
  }

  Future<void> requestLocation() async {
    _locationStatus = MapLocationStatus.requesting;
    _locationError = null;
    notifyListeners();
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        _locationStatus = MapLocationStatus.serviceDisabled;
        _locationError = 'Location services are disabled';
        notifyListeners();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _locationStatus = MapLocationStatus.denied;
        _locationError = 'Location permission denied';
        notifyListeners();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _setUserPosition(pos);
      _locationStatus = MapLocationStatus.granted;
      notifyListeners();
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        _setUserPosition(position);
        notifyListeners();
      });
    } catch (e) {
      _locationStatus = MapLocationStatus.error;
      _locationError = '$e';
      notifyListeners();
    }
  }

  double? distanceMetersTo(MapPin pin) {
    final p = _userPosition;
    if (p == null) return null;
    return _haversine(p.latitude, p.longitude, pin.latitude, pin.longitude);
  }

  double? bearingDegreesTo(MapPin pin) {
    final p = _userPosition;
    if (p == null) return null;
    return _bearing(p.latitude, p.longitude, pin.latitude, pin.longitude);
  }

  void _setUserPosition(Position position) {
    _previousUserPosition = _userPosition;
    _userPosition = position;
    _userBearingDegrees = _resolveUserBearing(position, _previousUserPosition);
  }

  double? _resolveUserBearing(Position current, Position? previous) {
    if (current.heading.isFinite && current.heading >= 0) {
      return current.heading;
    }
    if (previous == null) return _userBearingDegrees;
    final distance = _haversine(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
    if (distance < 1) return _userBearingDegrees;
    return _bearing(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _rad(lat1);
    final phi2 = _rad(lat2);
    final dl = _rad(lon2 - lon1);
    final y = math.sin(dl) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dl);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 2 : 1)} km';
  }

  static String formatWalkTime(double meters) {
    final seconds = meters / 1.4;
    if (seconds < 60) return '${seconds.round()} sec walk';
    final minutes = seconds / 60;
    if (minutes < 60) return '${minutes.round()} min walk';
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(1)} h walk';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }
}

extension ArchiveCategoryRemoteX on ArchiveCategory {
  String remotePathFor({required String subFolder, required String fileName}) {
    if (subFolder.isEmpty) return '$remoteDir/$fileName';
    return '$remoteDir/$subFolder/$fileName';
  }
}
