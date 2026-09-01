import '../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../components/notification.dart';
import 'controller.dart';
import 'data/settings.dart';
import '../../../components/navigation.dart';
import '../../../components/archive/models/pin.dart';
import '../../../components/filelist/empty_view.dart';

part 'widgets/circle_button.dart';
part 'widgets/panel.dart';
part 'widgets/sheet.dart';

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
  final MapSettings _settings = MapSettings.instance;
  final MapController _mapController = MapController();
  MapPin? _selectedPin;
  bool _initialCentered = false;
  bool _initialPinSelected = false;
  bool _mapReady = false;
  bool _saving = false;
  String? _failedTemplate;

  _MapMode _mode = _MapMode.browse;
  MapPickTarget? _pickTarget;
  late final bool _openedInPickMode;

  @override
  void initState() {
    super.initState();
    _controller = MapToolController()..addListener(_onChanged);
    _settings.addListener(_onChanged);
    unawaited(_settings.load());
    _openedInPickMode = widget.pickLocationFor != null;
    if (_openedInPickMode) {
      _mode = _MapMode.pick;
      _pickTarget = widget.pickLocationFor;
    }
    _controller.initialize();
  }

  @override
  void dispose() {
    _settings.removeListener(_onChanged);
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
    if (!_settings.autoCenter ||
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
    if (_settings.trackDevice) {
      final d = _controller.devicePosition;
      if (d != null && d.hasFix) return LatLng(d.latitude, d.longitude);
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

  /// Following is one mode with two targets, not two switches: [MapSettings]
  /// stores "follow" in `autoCenter` and "the target is the Flipper" in
  /// `trackDevice`. So exactly one of the two buttons can read as active, and
  /// tapping the active one stops following altogether.
  bool get _followingMe => _settings.autoCenter && !_settings.trackDevice;

  bool get _followingDevice => _settings.autoCenter && _settings.trackDevice;

  void _stopFollowing() {
    _settings.setAutoCenter(false);
    _settings.setTrackDevice(false);
  }

  void _toggleAutoCenter() {
    if (_followingMe) {
      _stopFollowing();
      return;
    }
    _settings.setTrackDevice(false);
    _settings.setAutoCenter(true);
    _centerOnTarget();
  }

  void _toggleTrackDevice() {
    if (_followingDevice) {
      _stopFollowing();
      return;
    }
    _settings.setTrackDevice(true);
    _settings.setAutoCenter(true);
    _centerOnTarget();
  }

  void _centerOnTarget() {
    final target = _activeTarget();
    if (target == null) {
      _controller.requestLocation();
      return;
    }
    if (_mapReady) _mapController.move(target, 17);
  }

  void _selectPin(MapPin pin) {
    if (_mode == _MapMode.pick) return;
    setState(() {
      _selectedPin = pin;
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
        context.l10n.mapSaveLocationFailed,
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
    context.showNotification(
      context.l10n.mapLocationSaved,
      type: QNotificationType.good,
    );
  }

  @override
  Widget build(BuildContext context) {
    final firmwareColors = context.appColors;
    final effectiveDark = _settings.darkFor(firmwareColors.isDark);
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
          return LayoutBuilder(
            builder: (_, constraints) {
              final wide = constraints.maxWidth >= 720;
              return Scaffold(
                backgroundColor: colors.background,
                extendBodyBehindAppBar: !wide,
                appBar: wide ? _buildAppBar(colors) : null,
                body: wide
                    ? _buildDesktopLayout(colors)
                    : _buildMobileLayout(colors),
              );
            },
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
            ? context.l10n.mapSetLocation
            : context.l10n.mapSetLocationFor(target.displayName),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: context.l10n.commonCancel,
          onPressed: _saving ? null : _exitPickMode,
        ),
        actions: [
          QPageAppBarAction(
            tooltip: context.l10n.mapSaveLocation,
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
      title: context.l10n.mapTitle,
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
          tooltip: context.l10n.mapAutoCenter,
          onPressed: _toggleAutoCenter,
          icon: Icon(
            Icons.my_location,
            color: _followingMe
                ? colors.onAccent
                : colors.onAccent.withValues(alpha: 0.5),
          ),
        ),
        QPageAppBarAction(
          tooltip: _controller.devicePosition != null
              ? context.l10n.mapTrackFlipper
              : context.l10n.mapNoDeviceLocation,
          onPressed: _controller.devicePosition == null
              ? null
              : _toggleTrackDevice,
          icon: Icon(
            Icons.gps_fixed,
            color: _followingDevice
                ? colors.onAccent
                : colors.onAccent.withValues(alpha: 0.5),
          ),
        ),
        QPageAppBarAction(
          tooltip: context.l10n.mapReloadFiles,
          onPressed: _controller.loading ? null : _controller.loadFiles,
          icon: const Icon(Icons.refresh),
        ),
        QPageAppBarAction(
          tooltip: context.l10n.mapSettingsEntry,
          onPressed: () => openRoute(context, AppRoute.mapSettings),
          icon: const Icon(Icons.settings),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// True while the browse mode has nothing to draw but a status screen.
  Widget? _buildBrowseGuard(QAppColors colors) {
    if (_mode != _MapMode.browse) return null;
    if (_controller.loading && _controller.pins.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final loadError = _controller.loadError;
    if (loadError != null && _controller.pins.isEmpty) {
      return ArchiveEmptyView(
        icon: Icons.map_outlined,
        title: context.l10n.mapNoPins,
        subtitle: loadError,
        actionLabel: context.l10n.mapTryAgain,
        onAction: _controller.loadFiles,
      );
    }
    return null;
  }

  Widget _buildDesktopLayout(QAppColors colors) {
    final guard = _buildBrowseGuard(colors);
    if (guard != null) return guard;
    return Row(
      children: [
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: colors.divider)),
            color: colors.card,
          ),
          child: _MapPanel(
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
              context.l10n.mapCoordinatesCopied,
              type: QNotificationType.good,
            ),
          ),
        ),
        Expanded(child: _buildMapStack(colors, desktopMode: true)),
      ],
    );
  }

  Widget _buildMobileLayout(QAppColors colors) {
    final guard = _buildBrowseGuard(colors);
    if (guard != null) {
      return Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: guard,
      );
    }
    final picking = _mode == _MapMode.pick;
    return Stack(
      children: [
        _buildMapStack(colors, desktopMode: false),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: picking
                  ? _buildPickControls(colors)
                  : _buildBrowseControls(colors),
            ),
          ),
        ),
        if (!picking)
          Positioned.fill(
            child: _MapSheet(
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
                context.l10n.mapCoordinatesCopied,
                type: QNotificationType.good,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBrowseControls(QAppColors colors) {
    final canDismiss = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Row(
      children: [
        if (canDismiss)
          _MapControl(
            colors: colors,
            icon: Icons.arrow_back,
            tooltip: context.l10n.commonClose,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        const Spacer(),
        _MapControl(
          colors: colors,
          icon: Icons.my_location,
          tooltip: context.l10n.mapAutoCenter,
          active: _followingMe,
          onTap: _toggleAutoCenter,
        ),
        const SizedBox(width: 8),
        _MapControl(
          colors: colors,
          icon: Icons.settings_remote,
          tooltip: _controller.devicePosition != null
              ? context.l10n.mapTrackFlipper
              : context.l10n.mapNoDeviceLocation,
          active: _followingDevice,
          onTap: _controller.devicePosition == null ? null : _toggleTrackDevice,
        ),
        const SizedBox(width: 8),
        _MapControl(
          colors: colors,
          icon: Icons.refresh,
          tooltip: context.l10n.mapReloadFiles,
          onTap: _controller.loading ? null : _controller.loadFiles,
        ),
        const SizedBox(width: 8),
        _MapControl(
          colors: colors,
          icon: Icons.settings,
          tooltip: context.l10n.mapSettingsEntry,
          onTap: () => openRoute(context, AppRoute.mapSettings),
        ),
      ],
    );
  }

  Widget _buildPickControls(QAppColors colors) {
    return Row(
      children: [
        _MapControl(
          colors: colors,
          icon: Icons.close,
          tooltip: context.l10n.commonCancel,
          onTap: _saving ? null : _exitPickMode,
        ),
        const Spacer(),
        _MapControl(
          colors: colors,
          icon: Icons.check,
          label: context.l10n.mapSaveLocation,
          active: true,
          onTap: _saving ? null : _savePickedLocation,
        ),
      ],
    );
  }

  // Shared map Stack used by both mobile and desktop layouts
  Widget _buildMapStack(QAppColors colors, {required bool desktopMode}) {
    final picking = _mode == _MapMode.pick;
    // Without an app bar the floating controls own the top strip and the sheet
    // owns the bottom one, so everything else is inset past them.
    final overlay = desktopMode
        ? 12.0
        : MediaQuery.paddingOf(context).top + 8 + kMapControl + 8;
    final sheet = (desktopMode || picking)
        ? 0.0
        : (_selectedPin != null ? kMapPanelPeek : kMapSheetThin);
    final tiles = _settings.resolve(dark: colors.isDark);
    if (_failedTemplate != null && _failedTemplate != tiles.urlTemplate) {
      _failedTemplate = null;
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: _initialZoom(),
            maxZoom: tiles.maxZoom,
            minZoom: 2,
            backgroundColor: colors.isDark
                ? const Color(0xFF1A1A1A)
                : const Color(0xFFFFFFFF),
            onMapReady: () {
              _mapReady = true;
              _maybeAutoCenter();
            },
            onPositionChanged: (_, hasGesture) {
              if (!hasGesture) return;
              if (!_settings.autoCenter && !_settings.trackDevice) return;
              _stopFollowing();
            },
            onTap: picking
                ? null
                : (_, _) => setState(() => _selectedPin = null),
          ),
          children: [
            TileLayer(
              key: ValueKey(tiles.urlTemplate),
              urlTemplate: tiles.urlTemplate,
              errorTileCallback: (_, _, _) => _reportTileFailure(tiles),
              subdomains: tiles.subdomains,
              userAgentPackageName: 'qunleashed',
              maxZoom: tiles.maxZoom,
              retinaMode:
                  tiles.retina &&
                  _settings.retina &&
                  RetinaMode.isHighDensity(context),
            ),
            MarkerLayer(
              markers: _buildMarkers(
                colors,
                hidePinId: picking ? _pickTarget?.localPath : null,
              ),
            ),
          ],
        ),
        if (picking) Positioned.fill(child: _buildPickOverlay(colors, overlay)),

        if (tiles.attribution.isNotEmpty)
          Positioned(
            left: 6,
            bottom: sheet + 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  tiles.attribution,
                  style: TextStyle(color: colors.textMuted, fontSize: 9.5),
                ),
              ),
            ),
          ),

        if (!picking && tiles.missingKey)
          Positioned(
            left: 12,
            right: 12,
            top: overlay,
            child: _tileNotice(colors, context.l10n.mapNeedsKeyTap),
          )
        else if (!picking && _failedTemplate == tiles.urlTemplate)
          Positioned(
            left: 12,
            right: 12,
            top: overlay,
            child: _tileNotice(
              colors,
              context.l10n.mapSourceNotAnswering(tiles.label),
            ),
          ),
      ],
    );
  }

  void _reportTileFailure(MapTileConfig tiles) {
    if (_failedTemplate == tiles.urlTemplate) return;
    _failedTemplate = tiles.urlTemplate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _tileNotice(QAppColors colors, String message) {
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openRoute(context, AppRoute.mapSettings),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: colors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MapPin> _sortedPins() {
    final sorted = [..._controller.pins];
    sorted.sort((a, b) => a.category.index.compareTo(b.category.index));
    return sorted;
  }

  Widget _buildPickOverlay(QAppColors colors, double top) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            top: top,
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
                        context.l10n.mapDragHint,
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
            child: const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
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
