part of '../page.dart';

const double kMapPanelHandle = 16;
const double kMapPanelHeader = 74;
const double kMapPanelPeek = kMapPanelHandle + kMapPanelHeader;

/// Height of the sheet with nothing selected: the grab bar and nothing else.
const double kMapSheetThin = 22;

/// Width of the floating panel on the desktop layout.
const double kMapPanelWidth = 320;

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.pins,
    required this.selected,
    required this.controller,
    required this.colors,
    required this.onSelect,
    required this.onClose,
    required this.onCopyCoords,
    this.onEdit,
    this.scrollController,
    this.showHandle = false,
    this.onHandleTap,
  });

  final List<MapPin> pins;
  final MapPin? selected;
  final MapToolController controller;
  final QAppColors colors;
  final ValueChanged<MapPin> onSelect;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback onCopyCoords;
  final ScrollController? scrollController;
  final bool showHandle;
  final VoidCallback? onHandleTap;

  @override
  Widget build(BuildContext context) {
    final pin = selected;
    final double headerExtent =
        (showHandle ? kMapPanelHandle : 0) +
        (pin != null ? kMapPanelHeader : 0);

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        if (headerExtent > 0)
          SliverPersistentHeader(
            pinned: true,
            delegate: _MapPanelHeaderDelegate(
              extent: headerExtent,
              background: colors.card,
              divider: pin != null ? colors.divider : null,
              child: Column(
                children: [
                  if (showHandle)
                    _MapPanelHandle(colors: colors, onTap: onHandleTap),
                  if (pin != null)
                    Expanded(
                      child: _MapPanelHeader(
                        pin: pin,
                        controller: controller,
                        colors: colors,
                        onClose: onClose,
                        onEdit: onEdit,
                        onCopyCoords: onCopyCoords,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (pin != null)
          SliverToBoxAdapter(
            child: _MapPinDetails(pin: pin, colors: colors),
          ),
        if (pins.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  context.l10n.mapNoPinsWithLocation,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: pins.length,
            itemBuilder: (_, i) => _MapPinTile(
              pin: pins[i],
              selected: pin?.id == pins[i].id,
              colors: colors,
              onTap: () => onSelect(pins[i]),
            ),
          ),
      ],
    );
  }
}

class _MapPanelHandle extends StatelessWidget {
  const _MapPanelHandle({required this.colors, this.onTap});

  final QAppColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: kMapPanelHandle,
        child: Center(
          child: Container(
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPanelHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _MapPanelHeaderDelegate({
    required this.extent,
    required this.background,
    required this.child,
    this.divider,
  });

  final double extent;
  final Color background;
  final Color? divider;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final line = divider;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: line == null ? null : Border(bottom: BorderSide(color: line)),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_MapPanelHeaderDelegate old) =>
      old.extent != extent ||
      old.background != background ||
      old.divider != divider ||
      old.child != child;
}

class _MapPanelHeader extends StatelessWidget {
  const _MapPanelHeader({
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
    final p = pin!;

    final distance = controller.distanceMetersTo(p);
    final bearing = controller.bearingDegreesTo(p);
    final coords =
        '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                _MapPinGlyph(pin: p, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onEdit != null)
                  _MapPanelIcon(
                    icon: Icons.edit_location_alt_outlined,
                    color: colors.accent,
                    tooltip: context.l10n.mapEditLocation,
                    onTap: onEdit!,
                  ),
                _MapPanelIcon(
                  icon: Icons.close_rounded,
                  color: colors.textMuted,
                  tooltip: context.l10n.mapDeselect,
                  onTap: onClose,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 15,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _facts(context, p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _distance(context, distance, bearing),
                const SizedBox(width: 6),
              ],
            ),
          ),
          SizedBox(
            height: 15,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Clipboard.setData(ClipboardData(text: coords));
                onCopyCoords();
              },
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      coords,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 11, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything identifying about the signal on one line, so the collapsed
  /// sheet already answers "what is this" without being opened.
  String _facts(BuildContext context, MapPin p) {
    final parts = <String>[];
    final freq = p.frequency;
    if (freq != null) parts.add(_formatFrequency(freq));
    final proto = p.protocol;
    if (proto != null) {
      parts.add(p.bit != null ? '$proto, ${p.bit} bit' : proto);
    }
    if (parts.isEmpty) parts.add(p.category.title);
    return parts.join('  ·  ');
  }

  Widget _distance(BuildContext context, double? distance, double? bearing) {
    if (distance == null) {
      final status = controller.locationStatus;
      if (status == MapLocationStatus.notSupported) {
        return const SizedBox.shrink();
      }
      if (status == MapLocationStatus.requesting ||
          status == MapLocationStatus.granted) {
        return Text(
          context.l10n.mapLocating,
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        );
      }
      // Asking again cannot raise a prompt once the OS has a standing denial or
      // the service is off, so the tap goes on to the system settings page.
      final blocked =
          status == MapLocationStatus.serviceDisabled ||
          controller.permanentlyDenied;
      return GestureDetector(
        onTap: controller.ensureLocation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              blocked ? Icons.settings : Icons.location_on_outlined,
              size: 13,
              color: colors.accent,
            ),
            const SizedBox(width: 3),
            Text(
              blocked
                  ? context.l10n.mapSettingsEntry
                  : context.l10n.mapEnableLocation,
              style: TextStyle(color: colors.accent, fontSize: 11),
            ),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.directions_walk, size: 13, color: colors.accent),
        const SizedBox(width: 3),
        Text(
          MapToolController.formatDistance(distance),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (bearing != null) ...[
          const SizedBox(width: 5),
          Transform.rotate(
            angle: bearing * 3.1415926 / 180,
            child: Icon(Icons.navigation, size: 12, color: colors.info),
          ),
          const SizedBox(width: 2),
          Text(
            _compassLabel(bearing),
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _MapPanelIcon extends StatelessWidget {
  const _MapPanelIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 15,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(child: Icon(icon, size: 17, color: color)),
        ),
      ),
    );
  }
}

class _MapPinDetails extends StatelessWidget {
  const _MapPinDetails({required this.pin, required this.colors});

  final MapPin pin;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (pin.frequency != null)
        (context.l10n.mapPinFrequency, _formatFrequency(pin.frequency!)),
      if (pin.protocol != null)
        (
          context.l10n.mapPinProtocol,
          pin.bit != null
              ? context.l10n.mapPinProtocolBits('${pin.protocol}', '${pin.bit}')
              : pin.protocol!,
        ),
      if (pin.uid != null) ('UID', pin.uid!),
      if (pin.key != null) (context.l10n.mapPinKey, pin.key!),
      if (pin.keyType != null) (context.l10n.mapPinKeyType, pin.keyType!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(color: colors.textPrimary, fontSize: 11),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: TextStyle(color: colors.textMuted),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPinTile extends StatelessWidget {
  const _MapPinTile({
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
    return Material(
      color: selected ? colors.accent.withValues(alpha: 0.12) : colors.card,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.divider.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              _MapPinGlyph(pin: pin, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      pin.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? colors.accent : colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      pin.category.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

class _MapPinGlyph extends StatelessWidget {
  const _MapPinGlyph({required this.pin, required this.size});

  final MapPin pin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pin.category.color,
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: SvgPicture.asset(
        _FlipperMapPageState._assetForPin(pin),
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      ),
    );
  }
}

String _compassLabel(double bearing) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((bearing + 22.5) / 45).floor() % 8];
}

String _formatFrequency(String raw) {
  final hz = int.tryParse(raw.trim());
  if (hz == null) return raw;
  return '${(hz / 1000000).toStringAsFixed(2)} MHz';
}
