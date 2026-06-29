import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../widgets/notification.dart';
import 'controller.dart';
import '../models/pin.dart';

part 'widgets/circle_button.dart';
part 'widgets/map_settings_panel.dart';
part 'widgets/pin_card.dart';
part 'widgets/sidebar.dart';

class FlipperMapPage extends StatefulWidget {
  const FlipperMapPage({super.key, this.focusPinPath, this.pickLocationFor});

  final String? focusPinPath;
  final MapPickTarget? pickLocationFor;

  @override
  State<FlipperMapPage> createState() => _FlipperMapPageState();
}

enum _MapMode { browse, pick }

class _FlipperMapPageState extends State<FlipperMapPage> {
  late final MapToolController _controller;
  final MapController _mapController = MapController();
  MapPin? _selectedPin;
  bool _initialCentered = false;
  bool _initialPinSelected = false;
  bool _mapReady = false;
  bool _saving = false;

  _MapMode _mode = _MapMode.browse;
  MapPickTarget? _pickTarget;
  late final bool _openedInPickMode;

  bool? _mapDarkOverride;
  bool _autoCenter = false;
  bool _followDevice = false;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = MapToolController()..addListener(_onChanged);
    _openedInPickMode = widget.pickLocationFor != null;
    if (_openedInPickMode) {
      _mode = _MapMode.pick;
      _pickTarget = widget.pickLocationFor;
    }
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
    if (_followDevice && _controller.devicePosition == null) {
      _followDevice = false;
    }
    _maybeSelectInitialPin();
    setState(() {});
    _maybeAutoCenter();
    _maybeFollowUser();
  }

  void _maybeAutoCenter() {
    if (!_mapReady || _initialCentered) return;
    if (_mode == _MapMode.pick) {
      final target = _pickTarget;
      if (target?.initialLatitude != null && target?.initialLongitude != null) {
        _initialCentered = true;
        _mapController.move(
          LatLng(target!.initialLatitude!, target.initialLongitude!),
          17,
        );
        return;
      }
      if (_controller.userPosition != null) {
        final p = _controller.userPosition!;
        _initialCentered = true;
        _mapController.move(LatLng(p.latitude, p.longitude), 17);
        return;
      }
      return;
    }
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

  void _maybeFollowUser() {
    if (!_autoCenter ||
        !_mapReady ||
        _mode != _MapMode.browse ||
        !_initialCentered) {
      return;
    }
    final target = _activeTarget();
    if (target == null) return;
    _mapController.move(target, _mapController.camera.zoom);
  }

  LatLng? _activeTarget() {
    if (_followDevice) {
      final d = _controller.devicePosition;
      if (d != null && d.hasFix) return LatLng(d.latitude, d.longitude);
      return null;
    }
    final p = _controller.userPosition;
    if (p == null) return null;
    return LatLng(p.latitude, p.longitude);
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

  void _centerOnTarget() {
    final target = _activeTarget();
    if (target == null) {
      if (!_followDevice) _controller.requestLocation();
      return;
    }
    if (_mapReady) _mapController.move(target, 17);
  }

  void _selectPin(MapPin pin) {
    if (_mode == _MapMode.pick) return;
    setState(() {
      _selectedPin = pin;
      _settingsOpen = false;
    });
    if (_mapReady) _mapController.move(LatLng(pin.latitude, pin.longitude), 17);
  }

  void _enterEditModeFor(MapPin pin) {
    setState(() {
      _mode = _MapMode.pick;
      _pickTarget = MapPickTarget(
        localPath: pin.path,
        remotePath: pin.remotePath,
        displayName: pin.name,
        initialLatitude: pin.latitude,
        initialLongitude: pin.longitude,
      );
      _selectedPin = null;
      _settingsOpen = false;
    });
    if (_mapReady) {
      _mapController.move(LatLng(pin.latitude, pin.longitude), 17);
    }
  }

  void _exitPickMode() {
    if (_openedInPickMode) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _mode = _MapMode.browse;
      _pickTarget = null;
    });
  }

  Future<void> _savePickedLocation() async {
    final target = _pickTarget;
    if (target == null || _saving) return;
    setState(() => _saving = true);
    final center = _mapController.camera.center;
    final ok = await _controller.writeCoordinates(
      localPath: target.localPath,
      remotePath: target.remotePath,
      latitude: center.latitude,
      longitude: center.longitude,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      context.showNotification(
        'Failed to save location',
        type: QNotificationType.error,
      );
      return;
    }
    final savedPath = target.localPath;
    if (_openedInPickMode) {
      Navigator.of(context).maybePop(true);
      return;
    }
    setState(() {
      _mode = _MapMode.browse;
      _pickTarget = null;
    });
    for (final p in _controller.pins) {
      if (p.path == savedPath) {
        setState(() => _selectedPin = p);
        if (_mapReady) _mapController.move(LatLng(p.latitude, p.longitude), 17);
        break;
      }
    }
    context.showNotification('Location saved', type: QNotificationType.good);
  }

  @override
  Widget build(BuildContext context) {
    final firmwareColors = context.appColors;
    final effectiveDark = _mapDarkOverride ?? firmwareColors.isDark;
    final mapColors = _resolveMapColors(firmwareColors, effectiveDark);

    final colorScheme =
        (effectiveDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
              primary: mapColors.accent,
              onPrimary: mapColors.onAccent,
              secondary: mapColors.info,
              surface: mapColors.card,
              onSurface: mapColors.textPrimary,
              error: mapColors.danger,
            );

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: mapColors.background,
        colorScheme: colorScheme,
        extensions: [mapColors],
      ),
      child: Builder(
        builder: (ctx) {
          final colors = ctx.appColors;
          return Scaffold(
            backgroundColor: colors.background,
            appBar: _buildAppBar(colors),
            body: _buildBody(colors),
          );
        },
      ),
    );
  }

  static QAppColors _resolveMapColors(QAppColors current, bool dark) {
    if (dark == current.isDark) return current;
    return QAppColors.build(
      dark ? Brightness.dark : Brightness.light,
      current.accent,
    );
  }

  PreferredSizeWidget _buildAppBar(QAppColors colors) {
    if (_mode == _MapMode.pick) {
      final target = _pickTarget;
      return QPageAppBar(
        title: target == null
            ? 'Set location'
            : 'Set location: ${target.displayName}',
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _saving ? null : _exitPickMode,
        ),
        actions: [
          QPageAppBarAction(
            tooltip: 'Save location',
            onPressed: _saving ? null : _savePickedLocation,
            icon: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onAccent,
                    ),
                  )
                : const Icon(Icons.check),
          ),
        ],
      );
    }
    return QPageAppBar(
      title: 'Signal Map',
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place, size: 20),
                const SizedBox(width: 4),
                Text(
                  '${_controller.pins.length}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        QPageAppBarAction(
          tooltip: 'Reload files',
          onPressed: _controller.loading ? null : _controller.loadFiles,
          icon: const Icon(Icons.refresh),
        ),
        QPageAppBarAction(
          tooltip: 'Map settings',
          onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          icon: Icon(
            Icons.settings,
            color: _settingsOpen
                ? colors.onAccent.withValues(alpha: 0.6)
                : null,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody(QAppColors colors) {
    if (_mode == _MapMode.browse &&
        _controller.loading &&
        _controller.pins.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final loadError = _controller.loadError;
    if (_mode == _MapMode.browse &&
        loadError != null &&
        _controller.pins.isEmpty) {
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
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
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

    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth >= 720) {
          return _buildDesktopLayout(colors);
        }
        return _buildMobileLayout(colors);
      },
    );
  }

  Widget _buildDesktopLayout(QAppColors colors) {
    return Row(
      children: [
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: colors.divider)),
            color: colors.card,
          ),
          child: _MapSidebar(
            pins: _sortedPins(),
            selected: _selectedPin,
            controller: _controller,
            colors: colors,
            onSelect: _selectPin,
            onClose: () => setState(() => _selectedPin = null),
            onEdit: _selectedPin != null
                ? () => _enterEditModeFor(_selectedPin!)
                : null,
            onCopyCoords: () => context.showNotification(
              'Coordinates copied',
              type: QNotificationType.good,
            ),
          ),
        ),
        Expanded(child: _buildMapStack(colors, desktopMode: true)),
      ],
    );
  }

  Widget _buildMobileLayout(QAppColors colors) {
    final picking = _mode == _MapMode.pick;
    return Stack(
      children: [
        _buildMapStack(colors, desktopMode: false),

        // Pin info card
        if (!picking && _selectedPin != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _PinCard(
              pin: _selectedPin!,
              controller: _controller,
              colors: colors,
              onClose: () => setState(() => _selectedPin = null),
              onEdit: () => _enterEditModeFor(_selectedPin!),
              onCopyCoords: () => context.showNotification(
                'Coordinates copied',
                type: QNotificationType.good,
              ),
            ),
          ),
      ],
    );
  }

  // Shared map Stack used by both mobile and desktop layouts
  Widget _buildMapStack(QAppColors colors, {required bool desktopMode}) {
    final picking = _mode == _MapMode.pick;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: _initialZoom(),
            maxZoom: 19,
            minZoom: 2,
            backgroundColor: (_mapDarkOverride ?? colors.isDark)
                ? const Color(0xFF1A1A1A)
                : const Color(0xFFFFFFFF),
            onMapReady: () {
              _mapReady = true;
              _maybeAutoCenter();
            },
            onTap: picking
                ? null
                : (_, _) => setState(() {
                    _selectedPin = null;
                    _settingsOpen = false;
                  }),
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
            MarkerLayer(
              markers: _buildMarkers(
                colors,
                hidePinId: picking ? _pickTarget?.localPath : null,
              ),
            ),
          ],
        ),
        if (picking) Positioned.fill(child: _buildPickOverlay(colors)),

        // Location button — on mobile moves up when card visible
        Positioned(
          right: 12,
          bottom: (!desktopMode && !picking && _selectedPin != null) ? 218 : 12,
          child: _CircleButton(
            colors: colors,
            icon: _followDevice ? Icons.gps_fixed : Icons.my_location,
            onTap: _centerOnTarget,
          ),
        ),

        // Settings floating panel
        if (_settingsOpen && _mode == _MapMode.browse)
          Positioned(
            top: 8,
            right: 8,
            child: _MapSettingsPanel(
              mapDark: colors.isDark,
              autoCenter: _autoCenter,
              followDevice: _followDevice,
              deviceAvailable: _controller.devicePosition != null,
              onMapDarkChanged: (v) => setState(() => _mapDarkOverride = v),
              onAutoCenterChanged: (v) => setState(() => _autoCenter = v),
              onFollowDeviceChanged: (v) {
                setState(() => _followDevice = v);
                _centerOnTarget();
              },
              onClose: () => setState(() => _settingsOpen = false),
            ),
          ),
      ],
    );
  }

  List<MapPin> _sortedPins() {
    final sorted = [..._controller.pins];
    sorted.sort((a, b) => a.category.index.compareTo(b.category.index));
    return sorted;
  }

  Widget _buildPickOverlay(QAppColors colors) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: colors.card.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Drag the map to position the pin, then tap the check to save.',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_on, size: 44, color: colors.accent),
            ),
          ),
          Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LatLng _initialCenter() {
    if (_mode == _MapMode.pick) {
      final target = _pickTarget;
      if (target?.initialLatitude != null && target?.initialLongitude != null) {
        return LatLng(target!.initialLatitude!, target.initialLongitude!);
      }
      final p = _controller.userPosition;
      if (p != null) return LatLng(p.latitude, p.longitude);
      return const LatLng(20, 0);
    }
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
    if (_mode == _MapMode.pick) return 17;
    if (_selectedPin != null) return 17;
    if (_controller.userPosition != null) return 16;
    if (_controller.pins.isNotEmpty) return 14;
    return 2;
  }

  List<Marker> _buildMarkers(QAppColors colors, {String? hidePinId}) {
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
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
            child: Transform.rotate(
              angle: bearing * 3.1415926 / 180,
              child: const Icon(
                Icons.navigation,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }
    final device = _controller.devicePosition;
    if (device != null && device.hasFix) {
      list.add(
        Marker(
          point: LatLng(device.latitude, device.longitude),
          width: 34,
          height: 34,
          child: Container(
            decoration: BoxDecoration(
              color: colors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
            child: const Icon(
              Icons.gps_fixed,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }
    final visiblePins = hidePinId == null
        ? _controller.pins
        : _controller.pins.where((pin) => pin.path != hidePinId).toList();
    final markerPoints = _spreadOverlappingPins(visiblePins);
    for (final entry in markerPoints.entries) {
      final pin = entry.key;
      final selected = _selectedPin?.id == pin.id;
      final pinColor = pin.category.color;
      list.add(
        Marker(
          point: entry.value,
          width: 42,
          height: 42,
          child: GestureDetector(
            onTap: () => _selectPin(pin),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pinColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.white : pinColor,
                  width: selected ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SvgPicture.asset(
                  _assetForPin(pin),
                  fit: BoxFit.contain,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
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
      final key =
          '${pin.latitude.toStringAsFixed(5)}:${pin.longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => <MapPin>[]).add(pin);
    }
    for (final group in groups.values) {
      if (group.length == 1) {
        final pin = group.first;
        points[pin] = LatLng(pin.latitude, pin.longitude);
        continue;
      }
      final centerLat =
          group.map((p) => p.latitude).reduce((a, b) => a + b) / group.length;
      final centerLon =
          group.map((p) => p.longitude).reduce((a, b) => a + b) / group.length;
      final radiusMeters = 10.0 + group.length.clamp(0, 8) * 2.0;
      for (var i = 0; i < group.length; i++) {
        final pin = group[i];
        final angle = (2 * 3.1415926 * i / group.length) - (3.1415926 / 2);
        points[pin] = _offsetLatLng(centerLat, centerLon, radiusMeters, angle);
      }
    }
    return points;
  }

  static LatLng _offsetLatLng(
    double latitude,
    double longitude,
    double meters,
    double angle,
  ) {
    const metersPerDegreeLatitude = 111320.0;
    final latRad = latitude * 3.1415926 / 180;
    final metersPerDegreeLongitude =
        metersPerDegreeLatitude * math.cos(latRad).abs().clamp(0.01, 1.0);
    final latOffset = math.sin(angle) * meters / metersPerDegreeLatitude;
    final lonOffset = math.cos(angle) * meters / metersPerDegreeLongitude;
    return LatLng(latitude + latOffset, longitude + lonOffset);
  }

  static String _assetForPin(MapPin pin) {
    return switch (pin.extension) {
      'sub' => 'assets/ic/fileformat/sub.svg',
      'nfc' => 'assets/ic/fileformat/nfc.svg',
      'rfid' => 'assets/ic/fileformat/rfid.svg',
      'ibtn' => 'assets/ic/fileformat/ibutton.svg',
      _ => pin.category.asset,
    };
  }
}
