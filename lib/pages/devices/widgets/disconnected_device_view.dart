import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/device_page_header.dart';
import '../../../widgets/device_shell.dart';
import 'firmware_carousel_card.dart';

class DisconnectedDeviceView extends StatelessWidget {
  const DisconnectedDeviceView({
    super.key,
    required this.onConnect,
  });

  final VoidCallback onConnect;
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
              const FirmwareCarouselCard(deviceVersion: null),
              const SizedBox(height: 14),
              FlipperPageCard(
                child: Column(
                  children: [
                    FlipperActionRow(
                      iconAsset: 'assets/flipper_svg/core/ic_bluetooth.svg',
                      label: 'Connect',
                      color: colors.accent,
                      onTap: onConnect,
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
          title: 'No device',
          subtitle: 'Flipper Zero',
          active: false,
        ),
      ],
    );
  }
}
