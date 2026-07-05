import 'package:flutter/material.dart';

import '../../services/notifications/push_service.dart';
import '../../theme/theme.dart';
import '../../widgets/page_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: const [
          _NotificationsCard(),
        ],
      ),
    );
  }
}

class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard();

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  bool _enabled = true;
  bool _devEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await PushService.instance.isNotificationsEnabled();
    final dev = await PushService.instance.isDevUpdatesEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _devEnabled = dev;
      });
    }
  }

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    PushService.instance.setNotificationsEnabled(value);
  }

  void _setDev(bool value) {
    setState(() => _devEnabled = value);
    PushService.instance.setDevUpdatesEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final supported = PushService.isSupported;
    return FlipperPageCard(
      title: 'Notifications',
      child: Column(
        children: [
          if (!supported)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                'Push notifications are not available on this platform.',
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ),
          _NotificationRow(
            title: 'Enable notifications',
            subtitle: 'Unleashed and official firmware releases.',
            trailing: Switch(
              value: _enabled,
              activeThumbColor: colors.accent,
              onChanged: supported ? _setEnabled : null,
            ),
          ),
          Divider(height: 1, color: colors.divider, indent: 14, endIndent: 14),
          _NotificationRow(
            title: 'Development builds',
            subtitle: 'Also get notified about new dev channel builds.',
            trailing: Switch(
              value: _devEnabled,
              activeThumbColor: colors.accent,
              onChanged: (supported && _enabled) ? _setDev : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}
