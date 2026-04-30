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
    required this.deviceFirmwareVersion,
    required this.buildDate,
    required this.internalFlash,
    required this.sdCard,
    required this.onSynchronize,
    required this.onOpenRemoteControl,
    required this.onOpenFullInfo,
    required this.onDisconnect,
  });

  final String deviceName;
  final bool infoLoading;
  final String deviceFirmwareVersion;
  final String buildDate;
  final String internalFlash;
  final String sdCard;
  final VoidCallback? onSynchronize;
  final VoidCallback onOpenRemoteControl;
  final VoidCallback onOpenFullInfo;
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
                deviceVersion: infoLoading ? '-' : deviceFirmwareVersion,
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
                    FlipperInfoLine(label: 'Firmware Version', value: deviceFirmwareVersion),
                    Divider(height: 1, color: colors.divider),
                    FlipperInfoLine(label: 'Build Date', value: buildDate),
                    Divider(height: 1, color: colors.divider),
                    FlipperInfoLine(label: 'Int. Flash (Used/Total)', value: internalFlash),
                    Divider(height: 1, color: colors.divider),
                    FlipperInfoLine(label: 'SD Card (Used/Total)', value: sdCard),
                    Divider(height: 1, color: colors.divider),
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_navigate.svg',
                      label: 'Full Info',
                      color: colors.accent,
                      onTap: onOpenFullInfo,
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
                      color: colors.textMuted,
                      onTap: null,
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
