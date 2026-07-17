import 'package:flutter/material.dart';

import '../../services/notifications/push_service.dart';
import '../../theme/theme.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_tile.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  bool _appReleases = true;
  bool _firmwareReleases = true;
  bool _firmwareDev = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appReleases = await PushService.instance.isAppReleasesEnabled();
    final firmwareReleases =
        await PushService.instance.isFirmwareReleasesEnabled();
    final firmwareDev = await PushService.instance.isFirmwareDevEnabled();
    if (mounted) {
      setState(() {
        _appReleases = appReleases;
        _firmwareReleases = firmwareReleases;
        _firmwareDev = firmwareDev;
      });
    }
  }

  void _setAppReleases(bool value) {
    setState(() => _appReleases = value);
    PushService.instance.setAppReleasesEnabled(value);
  }

  void _setFirmwareReleases(bool value) {
    setState(() => _firmwareReleases = value);
    PushService.instance.setFirmwareReleasesEnabled(value);
  }

  void _setFirmwareDev(bool value) {
    setState(() => _firmwareDev = value);
    PushService.instance.setFirmwareDevEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final supported = PushService.isSupported;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          if (!supported)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
              child: Text(
                'Push notifications are not available on this platform.',
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ),
          SettingsGroup(
            title: 'Application',
            children: [
              SettingsSwitchTile(
                title: 'App releases',
                subtitle: 'New qUnleashed app versions.',
                value: _appReleases,
                onChanged: supported ? _setAppReleases : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SettingsGroup(
            title: 'Firmware',
            children: [
              SettingsSwitchTile(
                title: 'Firmware releases',
                subtitle: 'Unleashed and official firmware releases.',
                value: _firmwareReleases,
                onChanged: supported ? _setFirmwareReleases : null,
              ),
              SettingsSwitchTile(
                title: 'Dev channel',
                subtitle: 'Also get notified about new dev channel builds.',
                value: _firmwareDev,
                onChanged:
                    (supported && _firmwareReleases) ? _setFirmwareDev : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
