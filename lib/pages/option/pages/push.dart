import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/notifications/push_service.dart';
import '../../../theme/theme.dart';

class _Toggle {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
}

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  bool _appReleases = true;
  bool _appDev = false;
  bool _firmwareReleases = true;
  bool _firmwareDev = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appReleases = await PushService.instance.isAppReleasesEnabled();
    final appDev = await PushService.instance.isAppDevEnabled();
    final firmwareReleases =
        await PushService.instance.isFirmwareReleasesEnabled();
    final firmwareDev = await PushService.instance.isFirmwareDevEnabled();
    if (mounted) {
      setState(() {
        _appReleases = appReleases;
        _appDev = appDev;
        _firmwareReleases = firmwareReleases;
        _firmwareDev = firmwareDev;
      });
    }
  }

  void _setAppReleases(bool value) {
    setState(() => _appReleases = value);
    PushService.instance.setAppReleasesEnabled(value);
  }

  void _setAppDev(bool value) {
    setState(() => _appDev = value);
    PushService.instance.setAppDevEnabled(value);
  }

  void _setFirmwareReleases(bool value) {
    setState(() => _firmwareReleases = value);
    PushService.instance.setFirmwareReleasesEnabled(value);
  }

  void _setFirmwareDev(bool value) {
    setState(() => _firmwareDev = value);
    PushService.instance.setFirmwareDevEnabled(value);
  }

  Widget _tile(BuildContext context, _Toggle t) {
    final colors = context.appColors;
    final enabled = t.onChanged != null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? colors.textPrimary : colors.textMuted,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: t.value,
          activeThumbColor: colors.accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: t.onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final unavailable = PushService.isUnavailable;
    final supported = PushService.isSupported && !unavailable;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(context.l10n.settingsNotificationsTitle),
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
                unavailable
                    ? context.l10n.pushUnsignedBuild
                    : context.l10n.pushUnsupportedPlatform,
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ),
          GroupedCardList<_Toggle>(
            title: context.l10n.pushGroupApplication,
            items: [
              _Toggle(
                title: context.l10n.pushAppReleases,
                subtitle: context.l10n.pushAppReleasesSubtitle,
                value: _appReleases,
                onChanged: supported ? _setAppReleases : null,
              ),
              _Toggle(
                title: context.l10n.pushDevChannel,
                subtitle: context.l10n.pushAppDevSubtitle,
                value: _appDev,
                onChanged: (supported && _appReleases) ? _setAppDev : null,
              ),
            ],
            onTap: (t) =>
                t.onChanged == null ? null : () => t.onChanged!(!t.value),
            itemBuilder: _tile,
          ),
          const SizedBox(height: 10),
          GroupedCardList<_Toggle>(
            title: context.l10n.pushGroupFirmware,
            items: [
              _Toggle(
                title: context.l10n.pushFirmwareReleases,
                subtitle: context.l10n.pushFirmwareReleasesSubtitle,
                value: _firmwareReleases,
                onChanged: supported ? _setFirmwareReleases : null,
              ),
              _Toggle(
                title: context.l10n.pushDevChannel,
                subtitle: context.l10n.pushFirmwareDevSubtitle,
                value: _firmwareDev,
                onChanged:
                    (supported && _firmwareReleases) ? _setFirmwareDev : null,
              ),
            ],
            onTap: (t) =>
                t.onChanged == null ? null : () => t.onChanged!(!t.value),
            itemBuilder: _tile,
          ),
        ],
      ),
    );
  }
}
