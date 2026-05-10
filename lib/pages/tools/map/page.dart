import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme.dart';
import 'controller.dart';
import 'models/pin.dart';

class FlipperMapPage extends StatefulWidget {
  const FlipperMapPage({super.key, this.focusPinPath});

  final String? focusPinPath;

  @override
  State<FlipperMapPage> createState() => _FlipperMapPageState();
}

class _FlipperMapPageState extends State<FlipperMapPage> {
  late final MapToolController _controller;
  final MapController _mapController = MapController();
  MapPin? _selectedPin;
  bool _initialCentered = false;
  bool _initialPinSelected = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _controller = MapToolController()..addListener(_onChanged);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _maybeSelectInitialPin();
    setState(() {});
    _maybeAutoCenter();
  }

  void _maybeAutoCenter() {
    if (!_mapReady || _initialCentered) return;
    final selected = _selectedPin;
    if (selected != null) {
      _initialCentered = true;
      _mapController.move(LatLng(selected.latitude, selected.longitude), 17);
    } else if (_controller.userPosition != null) {
      final p = _controller.userPosition!;
      _initialCentered = true;
      _mapController.move(LatLng(p.latitude, p.longitude), 16);
    } else if (_controller.pins.isNotEmpty) {
      _initialCentered = true;
      final first = _controller.pins.first;
      _mapController.move(LatLng(first.latitude, first.longitude), 14);
    }
  }

  void _maybeSelectInitialPin() {
    final path = widget.focusPinPath;
    if (_initialPinSelected || path == null || path.isEmpty) return;
    for (final pin in _controller.pins) {
      if (pin.path == path || pin.id == path) {
        _selectedPin = pin;
        _initialPinSelected = true;
        break;
      }
    }
  }

  void _centerOnUser() {
    final p = _controller.userPosition;
    if (p == null) {
      _controller.requestLocation();
      return;
    }
    if (_mapReady) _mapController.move(LatLng(p.latitude, p.longitude), 17);
  }

  void _selectPin(MapPin pin) {
    setState(() => _selectedPin = pin);
    if (_mapReady) _mapController.move(LatLng(pin.latitude, pin.longitude), 17);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: const Text('Signal Map'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${_controller.pins.length}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reload files',
            onPressed: _controller.loading ? null : _controller.loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(QAppColors colors) {
    if (_controller.loading && _controller.pins.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final loadError = _controller.loadError;
    if (loadError != null && _controller.pins.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 64, color: colors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No pins to show',
                style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                loadError,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                ),
                onPressed: _controller.loadFiles,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: _initialZoom(),
            maxZoom: 19,
            minZoom: 2,
            backgroundColor: const Color(0xFF1A1A1A),
            onMapReady: () {
              _mapReady = true;
              _maybeAutoCenter();
            },
            onTap: (_, _) => setState(() => _selectedPin = null),
          ),
          children: [
            TileLayer(
              urlTemplate: colors.isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'qunleashed',
              maxZoom: 19,
              retinaMode: RetinaMode.isHighDensity(context),
            ),
            MarkerLayer(markers: _buildMarkers(colors)),
          ],
        ),
        Positioned(
          right: 12,
          bottom: _selectedPin == null ? 12 : 168,
          child: Column(
            children: [
              _CircleButton(
                colors: colors,
                icon: Icons.my_location,
                onTap: _centerOnUser,
              ),
            ],
          ),
        ),
        if (_selectedPin != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _PinCard(
              pin: _selectedPin!,
              controller: _controller,
              colors: colors,
              onClose: () => setState(() => _selectedPin = null),
            ),
          ),
      ],
    );
  }

  LatLng _initialCenter() {
    final selected = _selectedPin;
    if (selected != null) return LatLng(selected.latitude, selected.longitude);
    final p = _controller.userPosition;
    if (p != null) return LatLng(p.latitude, p.longitude);
    if (_controller.pins.isNotEmpty) {
      final first = _controller.pins.first;
      return LatLng(first.latitude, first.longitude);
    }
    return const LatLng(20, 0);
  }

  double _initialZoom() {
    if (_selectedPin != null) return 17;
    if (_controller.userPosition != null) return 16;
    if (_controller.pins.isNotEmpty) return 14;
    return 2;
  }

  List<Marker> _buildMarkers(QAppColors colors) {
    final list = <Marker>[];
    final p = _controller.userPosition;
    if (p != null) {
      final bearing = _controller.userBearingDegrees ?? 0;
      list.add(
        Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 34,
          height: 34,
          child: Container(
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
            child: Transform.rotate(
              angle: bearing * 3.1415926 / 180,
              child: const Icon(Icons.navigation, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }
    final markerPoints = _spreadOverlappingPins(_controller.pins);
    for (final entry in markerPoints.entries) {
      final pin = entry.key;
      final selected = _selectedPin?.id == pin.id;
      list.add(
        Marker(
          point: entry.value,
          width: 42,
          height: 42,
          child: GestureDetector(
            onTap: () => _selectPin(pin),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.white : colors.accent,
                  width: selected ? 3 : 2,
                ),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SvgPicture.asset(
                  _assetForPin(pin),
                  fit: BoxFit.contain,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return list;
  }

  Map<MapPin, LatLng> _spreadOverlappingPins(List<MapPin> pins) {
    final points = <MapPin, LatLng>{};
    final groups = <String, List<MapPin>>{};
    for (final pin in pins) {
      final key = '${pin.latitude.toStringAsFixed(5)}:${pin.longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => <MapPin>[]).add(pin);
    }

    for (final group in groups.values) {
      if (group.length == 1) {
        final pin = group.first;
        points[pin] = LatLng(pin.latitude, pin.longitude);
        continue;
      }

      final centerLat = group.map((p) => p.latitude).reduce((a, b) => a + b) / group.length;
      final centerLon = group.map((p) => p.longitude).reduce((a, b) => a + b) / group.length;
      final radiusMeters = 10.0 + group.length.clamp(0, 8) * 2.0;
      for (var i = 0; i < group.length; i++) {
        final pin = group[i];
        final angle = (2 * 3.1415926 * i / group.length) - (3.1415926 / 2);
        points[pin] = _offsetLatLng(centerLat, centerLon, radiusMeters, angle);
      }
    }
    return points;
  }

  static LatLng _offsetLatLng(double latitude, double longitude, double meters, double angle) {
    const metersPerDegreeLatitude = 111320.0;
    final latRad = latitude * 3.1415926 / 180;
    final metersPerDegreeLongitude = metersPerDegreeLatitude * math.cos(latRad).abs().clamp(0.01, 1.0);
    final latOffset = math.sin(angle) * meters / metersPerDegreeLatitude;
    final lonOffset = math.cos(angle) * meters / metersPerDegreeLongitude;
    return LatLng(latitude + latOffset, longitude + lonOffset);
  }

  static String _assetForPin(MapPin pin) {
    return switch (pin.extension) {
      'sub' => 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
      'nfc' => 'assets/flipper_svg/archive/ic_fileformat_nfc.svg',
      'rfid' => 'assets/flipper_svg/archive/ic_fileformat_rf.svg',
      'ibtn' => 'assets/flipper_svg/archive/ic_fileformat_ibutton.svg',
      _ => pin.category.asset,
    };
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.colors, required this.icon, required this.onTap});

  final QAppColors colors;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: colors.accent, size: 22),
        ),
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.pin,
    required this.controller,
    required this.colors,
    required this.onClose,
  });

  final MapPin pin;
  final MapToolController controller;
  final QAppColors colors;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final distance = controller.distanceMetersTo(pin);
    final bearing = controller.bearingDegreesTo(pin);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.accent),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: SvgPicture.asset(
                    _FlipperMapPageState._assetForPin(pin),
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        pin.category.title,
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: colors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (distance != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.directions_walk, size: 16, color: colors.accent),
                    const SizedBox(width: 6),
                    Text(
                      '${MapToolController.formatDistance(distance)} вЂў ${MapToolController.formatWalkTime(distance)}',
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    if (bearing != null) ...[
                      const SizedBox(width: 8),
                      Transform.rotate(
                        angle: bearing * 3.1415926 / 180,
                        child: Icon(Icons.navigation, size: 16, color: colors.info),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _compass(bearing),
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              )
            else if (controller.locationStatus == MapLocationStatus.granted)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('LocatingвЂ¦', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accent,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: controller.requestLocation,
                  icon: const Icon(Icons.location_on_outlined, size: 16),
                  label: const Text('Enable location to see distance'),
                ),
              ),
            _kv(colors, 'Coordinates', '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}'),
            if (pin.frequency != null) _kv(colors, 'Frequency', _formatFrequency(pin.frequency!)),
            if (pin.protocol != null)
              _kv(colors, 'Protocol', pin.bit != null ? '${pin.protocol} (${pin.bit} bit)' : pin.protocol!),
            if (pin.uid != null) _kv(colors, 'UID', pin.uid!),
            if (pin.key != null) _kv(colors, 'Key', pin.key!),
            if (pin.keyType != null) _kv(colors, 'Key type', pin.keyType!),
            _kv(colors, 'Path', pin.path),
          ],
        ),
      ),
    );
  }

  static Widget _kv(QAppColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: colors.textPrimary, fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: colors.textMuted),
            ),
            TextSpan(text: value),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _formatFrequency(String raw) {
    final hz = int.tryParse(raw.trim());
    if (hz == null) return raw;
    return '${(hz / 1000000).toStringAsFixed(2)} MHz';
  }

  static String _compass(double bearing) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final i = ((bearing + 22.5) / 45).floor() % 8;
    return dirs[i];
  }
}
