import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../config.dart';
import '../../../theme.dart';
import '../../../widgets/notification.dart';
import 'controller.dart';
import 'models/pin.dart';

class FlipperMapPage extends StatefulWidget {
  const FlipperMapPage({
    super.key,
    this.focusPinPath,
    this.pickLocationFor,
  });

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
        _mapController.move(LatLng(target!.initialLatitude!, target.initialLongitude!), 17);
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
    if (!_autoCenter || !_mapReady || _mode != _MapMode.browse || !_initialCentered) return;
    final p = _controller.userPosition;
    if (p == null) return;
    _mapController.move(LatLng(p.latitude, p.longitude), _mapController.camera.zoom);
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
      context.showNotification('Failed to save location', type: QNotificationType.error);
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

    final colorScheme = (effectiveDark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
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

  /// Switches to the full unlshd or OFW firmware color scheme, scoped to this page only.
  static QAppColors _resolveMapColors(QAppColors current, bool dark) {
    if (dark == current.isDark) return current;
    final firmwares = QAppConfig.firmware.firmwares;
    final target = dark
        ? firmwares.firstWhere((f) => f.shortName == 'unlshd',
            orElse: () => firmwares.first)
        : firmwares.firstWhere((f) => f.shortName == 'ofw',
            orElse: () => firmwares.last);
    return QAppColors.fromFirmware(target);
  }

  PreferredSizeWidget _buildAppBar(QAppColors colors) {
    if (_mode == _MapMode.pick) {
      final target = _pickTarget;
      return AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _saving ? null : _exitPickMode,
        ),
        title: Text(
          target == null ? 'Set location' : 'Set location: ${target.displayName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Save location',
            onPressed: _saving ? null : _savePickedLocation,
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check),
          ),
        ],
      );
    }
    return AppBar(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      title: const Text('Signal Map'),
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
        IconButton(
          tooltip: 'Map settings',
          onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          icon: Icon(
            Icons.settings,
            color: _settingsOpen ? colors.onAccent.withValues(alpha: 0.6) : null,
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
    if (_mode == _MapMode.browse && loadError != null && _controller.pins.isEmpty) {
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
                    fontWeight: FontWeight.w700),
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
        Expanded(child: _buildMapStack(colors, desktopMode: true)),
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.divider)),
            color: colors.card,
          ),
          child: _MapSidebar(
            pins: _sortedPins(),
            selected: _selectedPin,
            controller: _controller,
            colors: colors,
            onSelect: _selectPin,
            onClose: () => setState(() => _selectedPin = null),
            onEdit: _selectedPin != null ? () => _enterEditModeFor(_selectedPin!) : null,
            onCopyCoords: () => context.showNotification(
              'Coordinates copied',
              type: QNotificationType.good,
            ),
          ),
        ),
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
            icon: Icons.my_location,
            onTap: _centerOnUser,
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
              onMapDarkChanged: (v) => setState(() => _mapDarkOverride = v),
              onAutoCenterChanged: (v) => setState(() => _autoCenter = v),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Drag the map to position the pin, then tap the check to save.',
                        style: TextStyle(color: colors.textPrimary, fontSize: 13),
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
        final angle =
            (2 * 3.1415926 * i / group.length) - (3.1415926 / 2);
        points[pin] =
            _offsetLatLng(centerLat, centerLon, radiusMeters, angle);
      }
    }
    return points;
  }

  static LatLng _offsetLatLng(
      double latitude, double longitude, double meters, double angle) {
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
      'sub' => 'assets/flipper_svg/archive/ic_fileformat_sub.svg',
      'nfc' => 'assets/flipper_svg/archive/ic_fileformat_nfc.svg',
      'rfid' => 'assets/flipper_svg/archive/ic_fileformat_rf.svg',
      'ibtn' => 'assets/flipper_svg/archive/ic_fileformat_ibutton.svg',
      _ => pin.category.asset,
    };
  }
}

class _MapSettingsPanel extends StatelessWidget {
  const _MapSettingsPanel({
    required this.mapDark,
    required this.autoCenter,
    required this.onMapDarkChanged,
    required this.onAutoCenterChanged,
    required this.onClose,
  });

  final bool mapDark;
  final bool autoCenter;
  final ValueChanged<bool> onMapDarkChanged;
  final ValueChanged<bool> onAutoCenterChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      elevation: 8,
      child: SizedBox(
        width: 248,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
              child: Row(
                children: [
                  Text(
                    'Map settings',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: colors.textMuted),
                    onPressed: onClose,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.15)),
            _SettingsRow(
              colors: colors,
              icon: Icons.dark_mode_outlined,
              label: 'Dark map tiles',
              subtitle: 'Switch between dark and light tiles',
              value: mapDark,
              onChanged: onMapDarkChanged,
            ),
            Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.1)),
            _SettingsRow(
              colors: colors,
              icon: Icons.my_location,
              label: 'Auto-center',
              subtitle: 'Follow my location',
              value: autoCenter,
              onChanged: onAutoCenterChanged,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final QAppColors colors;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                Text(subtitle,
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton(
      {required this.colors, required this.icon, required this.onTap});

  final QAppColors colors;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: colors.card,
        shape: const CircleBorder(),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          radius: 24,
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: colors.accent, size: 22),
          ),
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
    required this.onEdit,
    required this.onCopyCoords,
  });

  final MapPin pin;
  final MapToolController controller;
  final QAppColors colors;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onCopyCoords;

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
                    color: pin.category.color,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(5),
                  child: SvgPicture.asset(
                    _FlipperMapPageState._assetForPin(pin),
                    fit: BoxFit.contain,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        pin.category.title,
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit location',
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_location_alt_outlined,
                      color: colors.accent),
                ),
                IconButton(
                  tooltip: 'Close',
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
                      '${MapToolController.formatDistance(distance)} • ${MapToolController.formatWalkTime(distance)}',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    if (bearing != null) ...[
                      const SizedBox(width: 8),
                      Transform.rotate(
                        angle: bearing * 3.1415926 / 180,
                        child:
                            Icon(Icons.navigation, size: 16, color: colors.info),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _compass(bearing),
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              )
            else if (controller.locationStatus == MapLocationStatus.granted)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Locating…',
                    style: TextStyle(color: colors.textMuted, fontSize: 12)),
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
            _coordsRow(colors, pin, onCopyCoords),
            if (pin.frequency != null)
              _kv(colors, 'Frequency', _formatFrequency(pin.frequency!)),
            if (pin.protocol != null)
              _kv(
                colors,
                'Protocol',
                pin.bit != null
                    ? '${pin.protocol} (${pin.bit} bit)'
                    : pin.protocol!,
              ),
            if (pin.uid != null) _kv(colors, 'UID', pin.uid!),
            if (pin.key != null) _kv(colors, 'Key', pin.key!),
            if (pin.keyType != null) _kv(colors, 'Key type', pin.keyType!),
            _kv(colors, 'Path', pin.path),
          ],
        ),
      ),
    );
  }

  static Widget _coordsRow(
      QAppColors colors, MapPin pin, VoidCallback onCopy) {
    final value =
        '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Coordinates: ',
              style: TextStyle(color: colors.textMuted, fontSize: 12)),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                onCopy();
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style:
                          TextStyle(color: colors.textPrimary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 12, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ],
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
                style: TextStyle(color: colors.textMuted)),
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

class _MapSidebar extends StatelessWidget {
  const _MapSidebar({
    required this.pins,
    required this.selected,
    required this.controller,
    required this.colors,
    required this.onSelect,
    required this.onClose,
    required this.onCopyCoords,
    this.onEdit,
  });

  final List<MapPin> pins;
  final MapPin? selected;
  final MapToolController controller;
  final QAppColors colors;
  final ValueChanged<MapPin> onSelect;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback onCopyCoords;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SidebarInfoPanel(
          pin: selected,
          controller: controller,
          colors: colors,
          onClose: onClose,
          onEdit: onEdit,
          onCopyCoords: onCopyCoords,
        ),
        Divider(height: 1, color: colors.divider),
        Expanded(
          child: pins.isEmpty
              ? Center(
                  child: Text(
                    'No pins with location data',
                    style: TextStyle(color: colors.textMuted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: pins.length,
                  itemBuilder: (_, i) => _SidebarPinTile(
                    pin: pins[i],
                    selected: selected?.id == pins[i].id,
                    colors: colors,
                    onTap: () => onSelect(pins[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SidebarInfoPanel extends StatelessWidget {
  const _SidebarInfoPanel({
    required this.pin,
    required this.controller,
    required this.colors,
    required this.onClose,
    required this.onCopyCoords,
    this.onEdit,
  });

  final MapPin? pin;
  final MapToolController controller;
  final QAppColors colors;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback onCopyCoords;

  @override
  Widget build(BuildContext context) {
    final p = pin;
    if (p == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, size: 20, color: colors.textMuted),
            const SizedBox(width: 10),
            Text(
              'Select a pin from the list',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final distance = controller.distanceMetersTo(p);
    final bearing = controller.bearingDegreesTo(p);
    final coordsValue =
        '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: p.category.color, shape: BoxShape.circle),
                padding: const EdgeInsets.all(5),
                child: SvgPicture.asset(
                  _FlipperMapPageState._assetForPin(p),
                  fit: BoxFit.contain,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: Icon(Icons.edit_location_alt_outlined,
                      size: 18, color: colors.accent),
                  onPressed: onEdit,
                  tooltip: 'Edit location',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: colors.textMuted),
                onPressed: onClose,
                tooltip: 'Deselect',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Distance / bearing row
          if (distance != null)
            Row(
              children: [
                Icon(Icons.directions_walk, size: 14, color: colors.accent),
                const SizedBox(width: 4),
                Text(
                  '${MapToolController.formatDistance(distance)} · ${MapToolController.formatWalkTime(distance)}',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                if (bearing != null) ...[
                  const SizedBox(width: 6),
                  Transform.rotate(
                    angle: bearing * 3.1415926 / 180,
                    child: Icon(Icons.navigation, size: 13, color: colors.info),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _compass(bearing),
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            )
          else if (controller.locationStatus == MapLocationStatus.granted)
            Text('Locating…',
                style: TextStyle(color: colors.textMuted, fontSize: 12))
          else
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: colors.accent,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: controller.requestLocation,
              icon: const Icon(Icons.location_on_outlined, size: 14),
              label: const Text('Enable location', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 4),
          // Coordinates row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Clipboard.setData(ClipboardData(text: coordsValue));
              onCopyCoords();
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    coordsValue,
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.copy, size: 11, color: colors.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _compass(double bearing) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((bearing + 22.5) / 45).floor() % 8];
  }
}

class _SidebarPinTile extends StatelessWidget {
  const _SidebarPinTile({
    required this.pin,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final MapPin pin;
  final bool selected;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? colors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: pin.category.color,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(6),
              child: SvgPicture.asset(
                _FlipperMapPageState._assetForPin(pin),
                fit: BoxFit.contain,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pin.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? colors.accent : colors.textPrimary,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    pin.category.title,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.chevron_right, size: 16, color: colors.accent),
          ],
        ),
      ),
    );
  }
}
