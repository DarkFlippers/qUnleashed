part of '../page.dart';

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
                  color: p.category.color,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(5),
                child: SvgPicture.asset(
                  _FlipperMapPageState._assetForPin(p),
                  fit: BoxFit.contain,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
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
                    fontSize: 14,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: Icon(
                    Icons.edit_location_alt_outlined,
                    size: 18,
                    color: colors.accent,
                  ),
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
                    fontWeight: FontWeight.w600,
                  ),
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
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            )
          else if (controller.locationStatus == MapLocationStatus.granted)
            Text(
              'Locating…',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            )
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
              label: const Text(
                'Enable location',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
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
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
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
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
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
