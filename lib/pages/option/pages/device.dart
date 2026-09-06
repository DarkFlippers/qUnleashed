import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../services/connection/device_settings.dart';
import '../../../services/localization/l10n.dart';
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
  final ValueChanged<bool> onChanged;
}

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({super.key});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  final DeviceSettings _settings = DeviceSettings.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
  }

  Widget _tile(BuildContext context, _Toggle t) {
    final colors = context.appColors;
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
                  color: colors.textPrimary,
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
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final colors = context.appColors;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(context.l10n.settingsDeviceTitle),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              GroupedCardList<_Toggle>(
                title: context.l10n.deviceGroupAutoConnect,
                items: [
                  _Toggle(
                    title: context.l10n.deviceAutoConnectUsb,
                    subtitle: context.l10n.deviceAutoConnectUsbSubtitle,
                    value: _settings.autoConnectUsb,
                    onChanged: _settings.setAutoConnectUsb,
                  ),
                  _Toggle(
                    title: context.l10n.deviceAutoConnectBle,
                    subtitle: context.l10n.deviceAutoConnectBleSubtitle,
                    value: _settings.autoConnectBle,
                    onChanged: _settings.setAutoConnectBle,
                  ),
                ],
                onTap: (t) => () => t.onChanged(!t.value),
                itemBuilder: _tile,
              ),
              const SizedBox(height: 10),
              GroupedCardList<_Toggle>(
                title: context.l10n.deviceGroupSync,
                items: [
                  _Toggle(
                    title: context.l10n.deviceSyncTime,
                    subtitle: context.l10n.deviceSyncTimeSubtitle,
                    value: _settings.syncTimeOnStart,
                    onChanged: _settings.setSyncTimeOnStart,
                  ),
                ],
                onTap: (t) => () => t.onChanged(!t.value),
                itemBuilder: _tile,
              ),
            ],
          ),
        );
      },
    );
  }
}
