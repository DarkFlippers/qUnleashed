import 'package:flutter/material.dart';

import '../../services/notifications/push_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
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
    final supported = PushService.isSupported;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          if (!supported)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Push notifications are not available on this platform.',
              ),
            ),
          const ListTile(
            title: Text('Release updates'),
            subtitle: Text('Unleashed and official releases. Always on.'),
            trailing: Icon(Icons.check_circle, color: Colors.green),
          ),
          SwitchListTile(
            title: const Text('Development builds'),
            subtitle: const Text('Get notified about new dev channel builds.'),
            value: _devEnabled,
            onChanged: (supported && !_busy) ? _setDev : null,
          ),
        ],
      ),
    );
  }
}
