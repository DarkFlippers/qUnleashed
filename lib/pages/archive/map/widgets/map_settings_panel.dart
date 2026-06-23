part of '../page.dart';

class _MapSettingsPanel extends StatelessWidget {
  const _MapSettingsPanel({
    required this.mapDark,
    required this.autoCenter,
    required this.followDevice,
    required this.deviceAvailable,
    required this.onMapDarkChanged,
    required this.onAutoCenterChanged,
    required this.onFollowDeviceChanged,
    required this.onClose,
  });

  final bool mapDark;
  final bool autoCenter;
  final bool followDevice;
  final bool deviceAvailable;
  final ValueChanged<bool> onMapDarkChanged;
  final ValueChanged<bool> onAutoCenterChanged;
  final ValueChanged<bool> onFollowDeviceChanged;
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
              subtitle: followDevice
                  ? 'Follow Flipper location'
                  : 'Follow my location',
              value: autoCenter,
              onChanged: onAutoCenterChanged,
            ),
            Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.1)),
            _SettingsRow(
              colors: colors,
              icon: Icons.gps_fixed,
              label: 'Track Flipper',
              subtitle: deviceAvailable
                  ? 'Center and follow the device'
                  : 'No device location yet',
              value: followDevice,
              onChanged: deviceAvailable ? onFollowDeviceChanged : null,
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
