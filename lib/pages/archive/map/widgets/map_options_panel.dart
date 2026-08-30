part of '../page.dart';

class _MapOptionsPanel extends StatelessWidget {
  const _MapOptionsPanel({
    required this.colors,
    required this.settings,
    required this.deviceAvailable,
    required this.onAutoCenterChanged,
    required this.onTrackDeviceChanged,
    required this.onOpenSettings,
    required this.onClose,
  });

  final QAppColors colors;
  final MapSettings settings;
  final bool deviceAvailable;
  final ValueChanged<bool> onAutoCenterChanged;
  final ValueChanged<bool> onTrackDeviceChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
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
                    'Map options',
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
            _OptionRow(
              colors: colors,
              icon: Icons.my_location,
              label: 'Auto-center',
              subtitle: settings.trackDevice
                  ? 'Follow Flipper location'
                  : 'Follow my location',
              value: settings.autoCenter,
              onChanged: onAutoCenterChanged,
            ),
            Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.1)),
            _OptionRow(
              colors: colors,
              icon: Icons.gps_fixed,
              label: 'Track Flipper',
              subtitle: deviceAvailable
                  ? 'Center and follow the device'
                  : 'No device location yet',
              value: settings.trackDevice,
              onChanged: deviceAvailable ? onTrackDeviceChanged : null,
            ),
            Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.15)),
            InkWell(
              onTap: onOpenSettings,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18, color: colors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Map settings',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Tile source, design, keys',
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
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
  final ValueChanged<bool>? onChanged;

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
                Text(
                  label,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
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
