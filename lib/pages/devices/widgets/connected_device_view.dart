import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/device_page_header.dart';
import '../../../widgets/device_shell.dart';
import 'device_navigate_icon.dart';
import 'firmware_carousel_card.dart';

class ConnectedDeviceView extends StatelessWidget {
  const ConnectedDeviceView({
    super.key,
    required this.deviceName,
    required this.infoLoading,
    required this.deviceInfo,
    required this.deviceInfoEntries,
    required this.onSynchronize,
    required this.onPlayAlert,
    required this.onOpenRemoteControl,
    required this.onOpenFullInfo,
    required this.onExport,
    required this.onDisconnect,
  });

  final String deviceName;
  final bool infoLoading;
  final Map<String, String> deviceInfo;
  final List<MapEntry<String, String>> deviceInfoEntries;
  final VoidCallback? onSynchronize;
  final VoidCallback? onPlayAlert;
  final VoidCallback onOpenRemoteControl;
  final VoidCallback onOpenFullInfo;
  final VoidCallback onExport;
  final VoidCallback onDisconnect;

  static const double _headerContentHeight = 114;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = topInset + _headerContentHeight;

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.only(top: headerHeight + 14, bottom: 14),
            children: [
              FirmwareCarouselCard(
                deviceVersion: infoLoading || deviceInfoEntries.isEmpty ? '-' : deviceInfoEntries.first.value,
                deviceInfo: deviceInfo,
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_controller.svg',
                      label: 'Remote Control',
                      color: colors.textPrimary,
                      trailing: DeviceNavigateIcon(color: colors.textMuted),
                      onTap: onOpenRemoteControl,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Control your Flipper Zero remotely via mobile phone',
                          style: TextStyle(fontSize: 12, color: colors.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                title: 'Device Info',
                trailing: InkWell(
                  onTap: onOpenFullInfo,
                  child: DeviceNavigateIcon(color: colors.textMuted),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < deviceInfoEntries.length; i++) ...[
                      FlipperInfoLine(
                        label: deviceInfoEntries[i].key,
                        value: deviceInfoEntries[i].value,
                      ),
                      if (i != deviceInfoEntries.length - 1)
                        Divider(height: 1, color: colors.divider),
                    ],
                    Divider(height: 1, color: colors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_navigate.svg',
                      label: 'Full Info',
                      color: colors.accent,
                      onTap: onOpenFullInfo,
                    ),
                    Divider(height: 1, color: colors.divider),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onExport,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Icon(Icons.copy, color: colors.accent, size: 20),
                              ),
                              Expanded(
                                child: Text(
                                  'Export',
                                  style: TextStyle(
                                    color: colors.accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_syncing.svg',
                      label: 'Synchronize',
                      color: onSynchronize == null ? colors.textMuted : colors.accent,
                      onTap: onSynchronize,
                    ),
                    Divider(height: 1, color: colors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_ring.svg',
                      label: 'Play Alert on Flipper',
                      color: onPlayAlert == null ? colors.textMuted : colors.accent,
                      onTap: onPlayAlert,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_bluetooth_disable.svg',
                      label: 'Disconnect',
                      color: colors.accent,
                      onTap: onDisconnect,
                    ),
                    Divider(height: 1, color: colors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/info/ic_disconnection.svg',
                      label: 'Forget Flipper',
                      color: colors.danger,
                      onTap: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DevicePageHeader(
          topInset: topInset,
          headerHeight: headerHeight,
          title: deviceName,
          subtitle: 'Flipper Zero',
          active: true,
        ),
      ],
    );
  }
}
