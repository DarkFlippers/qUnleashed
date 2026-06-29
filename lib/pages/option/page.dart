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
  bool _devEnabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await PushService.instance.isDevUpdatesEnabled();
    if (mounted) setState(() => _devEnabled = enabled);
  }

  Future<void> _setDev(bool value) async {
    setState(() {
      _devEnabled = value;
      _busy = true;
    });
    await PushService.instance.setDevUpdatesEnabled(value);
    if (mounted) setState(() => _busy = false);
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
            title: 'Release updates',
            subtitle: 'Unleashed and official releases. Always on.',
            trailing: Icon(Icons.check_circle, color: colors.success, size: 22),
          ),
          Divider(height: 1, color: colors.divider, indent: 14, endIndent: 14),
          _NotificationRow(
            title: 'Development builds',
            subtitle: 'Get notified about new dev channel builds.',
            trailing: Switch(
              value: _devEnabled,
              activeThumbColor: colors.accent,
              onChanged: (supported && !_busy) ? _setDev : null,
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
