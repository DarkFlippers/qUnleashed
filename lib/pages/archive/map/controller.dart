import '../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../../services/logging.dart';
import '../../../services/rpc/gps/gps_responder.dart';
import '../../../components/archive/parser.dart';
import '../../../services/archive/storage.dart';
import '../../../components/archive/category.dart';
import '../../../components/archive/models/pin.dart';

enum MapLocationStatus {
  idle,
  requesting,
  granted,
  denied,
  serviceDisabled,
  notSupported,
  error,
}

class MapToolController extends ChangeNotifier with WidgetsBindingObserver {
  MapToolController({ArchiveStorage? storage, FlipperClient? client})
    : _storage = storage ?? ArchiveStorage(),
      _client = client ?? FlipperOneClient().get();

  final ArchiveStorage _storage;
  final FlipperClient _client;

  bool _disposed = false;

  bool _loading = false;
  String? _loadError;
  List<MapPin> _pins = const [];
  MapLocationStatus _locationStatus = MapLocationStatus.idle;
  String? _locationError;
  bool _permanentlyDenied = false;
  Position? _userPosition;
  Position? _previousUserPosition;
  double? _userBearingDegrees;
  GpsFix? _devicePosition;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<FlipperConnectionState>? _connSub;
  StreamSubscription<Map<String, String>>? _deviceInfoSub;
  StreamSubscription<GpsFix>? _deviceLocSub;

  bool get loading => _loading;
  String? get loadError => _loadError;
  List<MapPin> get pins => _pins;
  MapLocationStatus get locationStatus => _locationStatus;
  String? get locationError => _locationError;
  bool get permanentlyDenied => _permanentlyDenied;
  Position? get userPosition => _userPosition;
  double? get userBearingDegrees => _userBearingDegrees;
  GpsFix? get devicePosition => _devicePosition;
  bool get isFlipperConnected => _client.isConnected;

  /// Every state change funnels through here: the async paths below outlive the
  /// page whenever it is closed mid-request, and a bare notifyListeners() on a
  /// disposed ChangeNotifier throws.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _connSub ??= _client.connectionStream.listen(_onConnectionChange);
    _deviceInfoSub ??= _client.deviceInfoUpdates.listen(_onDeviceInfo);
    _deviceLocSub ??= _client.flipperLocationStream().listen(_onDeviceLocation);
    await loadFiles();
    await requestLocation();
  }

  /// Retries the location handshake when the app comes back to the foreground:
  /// the user may have just granted the permission or switched GPS on in the
  /// system settings, and nothing else would tell us about it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || state != AppLifecycleState.resumed) return;
    switch (_locationStatus) {
      case MapLocationStatus.denied:
      case MapLocationStatus.serviceDisabled:
      case MapLocationStatus.error:
        requestLocation();
      case MapLocationStatus.idle:
      case MapLocationStatus.requesting:
      case MapLocationStatus.granted:
      case MapLocationStatus.notSupported:
        break;
    }
  }

  void _onDeviceLocation(GpsFix fix) {
    if (_disposed || !fix.hasFix) return;
    _devicePosition = fix;
    _notify();
  }

  void _onConnectionChange(FlipperConnectionState s) {
    if (_disposed) return;
    if (s.connected && s.device != null) {
      loadFiles();
    } else if (!s.connected && _devicePosition != null) {
      _devicePosition = null;
      _notify();
    }
  }

  void _onDeviceInfo(Map<String, String> patch) {
    if (_disposed) return;
    final name = patch['hardware_name'] ?? patch['device_name'];
    if (name != null && name.isNotEmpty) {
      loadFiles();
    }
  }

  Future<String?> _resolveDeviceName() async {
    final connected = _client.getName();
    if (connected != null && connected.isNotEmpty) return connected;
    return _storage.readLastDeviceName();
  }

  Future<void> loadFiles() async {
    if (_disposed) return;
    _loading = true;
    _loadError = null;
    _notify();
    try {
      final deviceName = await _resolveDeviceName();
      if (_disposed) return;
      if (deviceName == null || deviceName.isEmpty) {
        _pins = const [];
        _loadError = l10n.mapNoSyncedFlipper;
        return;
      }
      final entries = await _storage.listAll(deviceName);
      if (_disposed) return;
      final out = <MapPin>[];
      for (final entry in entries) {
        if (!entry.category.locationSupport) continue;
        final pin = await _parseFile(entry);
        if (pin != null) out.add(pin);
      }
      _pins = out;
    } catch (e) {
      _loadError = '$e';
    } finally {
      _loading = false;
      _notify();
    }
  }

  String _remotePathFor(LocalKeyEntry entry) {
    final fileName = '${entry.name}.${entry.extension}';
    final dir = ArchiveCategory.remoteDirOf(entry.flipperDir);
    if (entry.subFolder.isEmpty) return '$dir/$fileName';
    return '$dir/${entry.subFolder}/$fileName';
  }

  Future<MapPin?> _parseFile(LocalKeyEntry entry) async {
    try {
      final file = io.File(entry.path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();

      // Parse geo-coordinates (not handled by archive metadata parser)
      double? lat;
      double? lon;
      for (final raw in content.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final lower = line.toLowerCase();
        final colon = line.indexOf(':');
        if (colon < 0) continue;
        final value = line.substring(colon + 1).trim();
        if (lower.startsWith('latitude:') ||
            lower.startsWith('latitute:') ||
            lower.startsWith('lat:')) {
          lat = double.tryParse(value);
        } else if (lower.startsWith('longitude:') ||
            lower.startsWith('lon:') ||
            lower.startsWith('lng:')) {
          lon = double.tryParse(value);
        }
      }
      if (lat == null || lon == null) return null;
      if (lat == 0 && lon == 0) return null;

      final meta = await parseArchiveKeyMeta(entry.category, entry.path);
      return MapPin(
        id: entry.path,
        name: entry.name,
        path: entry.path,
        fileName: '${entry.name}.${entry.extension}',
        extension: entry.extension.toLowerCase(),
        subFolder: entry.subFolder,
        category: entry.category,
        remotePath: _remotePathFor(entry),
        latitude: lat,
        longitude: lon,
        content: content,
        frequency: meta?.meta['frequency'],
        protocol: meta?.protocol,
        bit: meta?.meta['bit'],
        uid: meta?.meta['uid'],
        key: meta?.meta['data'],
        keyType: meta?.meta['key_type'],
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

  static String _patchCoordinates(
    String original,
    double latitude,
    double longitude,
  ) {
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
    if (_disposed || _locationStatus == MapLocationStatus.requesting) return;
    _locationStatus = MapLocationStatus.requesting;
    _locationError = null;
    _notify();
    try {
      // Permission first, service second. Probing the service up front meant a
      // phone with GPS switched off — and a desktop build that had never been
      // authorised — bailed out before the system prompt was ever raised.
      var permission = await Geolocator.checkPermission();
      if (_disposed) return;
      if (permission == LocationPermission.denied) {
        // A prompt that never reaches the screen would otherwise wedge the
        // controller in `requesting` and make every later retry a no-op.
        permission = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 90),
          onTimeout: () => LocationPermission.denied,
        );
      }
      if (_disposed) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _permanentlyDenied = permission == LocationPermission.deniedForever;
        _locationStatus = MapLocationStatus.denied;
        _locationError = l10n.mapLocationDenied;
        _notify();
        return;
      }
      _permanentlyDenied = false;

      // A cached fix lets the map centre and distances appear immediately,
      // before the first GNSS lock lands.
      final cached = await Geolocator.getLastKnownPosition();
      if (_disposed) return;
      if (cached != null) _setUserPosition(cached);

      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (_disposed) return;
      if (!serviceOn) {
        _locationStatus = MapLocationStatus.serviceDisabled;
        _locationError = l10n.mapLocationDisabled;
        _notify();
        return;
      }

      _locationStatus = MapLocationStatus.granted;
      _notify();

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
        if (_disposed) return;
        _setUserPosition(pos);
        _notify();
      } catch (_) {
        // No fresh fix yet; the stream below keeps trying.
      }

      if (_disposed) return;
      _posSub?.cancel();
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            (position) {
              if (_disposed) return;
              _setUserPosition(position);
              _notify();
            },
            // kCLErrorLocationUnknown and friends are transient: Core Location
            // keeps trying, so this is a log line, not a user-facing failure.
            onError: (Object e) => LogService.log('[Map] location stream: $e'),
          );
    } on MissingPluginException {
      _locationStatus = MapLocationStatus.notSupported;
      _notify();
    } on UnimplementedError {
      _locationStatus = MapLocationStatus.notSupported;
      _notify();
    } catch (e) {
      _locationStatus = MapLocationStatus.error;
      _locationError = '$e';
      _notify();
    }
  }

  /// Asks for location and, when asking cannot help — a permanent denial or a
  /// switched-off service, where the OS raises no prompt at all — hands the
  /// user over to the system page that can.
  Future<void> ensureLocation() async {
    await requestLocation();
    if (_locationStatus == MapLocationStatus.granted ||
        _locationStatus == MapLocationStatus.notSupported) {
      return;
    }
    if (_permanentlyDenied ||
        _locationStatus == MapLocationStatus.serviceDisabled) {
      await openLocationSettings();
    }
  }

  /// Opens the system page where the user can undo a permanent denial or switch
  /// the location service back on.
  Future<void> openLocationSettings() {
    return _permanentlyDenied
        ? Geolocator.openAppSettings()
        : Geolocator.openLocationSettings();
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
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _rad(lat1);
    final phi2 = _rad(lat2);
    final dl = _rad(lon2 - lon1);
    final y = math.sin(dl) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dl);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static String formatDistance(double meters) {
    if (meters < 1000) return l10n.mapMeters(meters.round());
    return l10n.mapKilometers(
      (meters / 1000).toStringAsFixed(meters < 10000 ? 2 : 1),
    );
  }

  static String formatWalkTime(double meters) {
    final seconds = meters / 1.4;
    if (seconds < 60) return l10n.mapWalkSeconds(seconds.round());
    final minutes = seconds / 60;
    if (minutes < 60) return l10n.mapWalkMinutes(minutes.round());
    final hours = minutes / 60;
    return l10n.mapWalkHours(hours.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _connSub?.cancel();
    _deviceInfoSub?.cancel();
    _deviceLocSub?.cancel();
    super.dispose();
  }
}

extension ArchiveCategoryRemoteX on ArchiveCategory {
  String remotePathFor({required String subFolder, required String fileName}) {
    if (subFolder.isEmpty) return '$remoteDir/$fileName';
    return '$remoteDir/$subFolder/$fileName';
  }
}
