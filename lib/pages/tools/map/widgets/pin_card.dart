part of '../page.dart';

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
                    children: [
                      Text(
                        pin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        pin.category.title,
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit location',
                  onPressed: onEdit,
                  icon: Icon(
                    Icons.edit_location_alt_outlined,
                    color: colors.accent,
                  ),
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (bearing != null) ...[
                      const SizedBox(width: 8),
                      Transform.rotate(
                        angle: bearing * 3.1415926 / 180,
                        child: Icon(
                          Icons.navigation,
                          size: 16,
                          color: colors.info,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _compass(bearing),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else if (controller.locationStatus == MapLocationStatus.granted)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Locating…',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
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

  static Widget _coordsRow(QAppColors colors, MapPin pin, VoidCallback onCopy) {
    final value =
        '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Coordinates: ',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
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
                      style: TextStyle(color: colors.textPrimary, fontSize: 12),
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
