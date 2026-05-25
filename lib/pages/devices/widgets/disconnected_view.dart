import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/page_card.dart';
import 'firmware_carousel_card.dart';
import 'page_header.dart';

class DisconnectedDeviceView extends StatelessWidget {
  const DisconnectedDeviceView({super.key, required this.onConnect});

  final VoidCallback onConnect;
  static const double _headerContentHeight = 114;
  static const double _contentMaxWidth = 1120;

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
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: Column(
                    children: [
                      const FirmwareCarouselCard(
                        deviceVersion: null,
                        deviceInfo: {},
                      ),
                      const SizedBox(height: 14),
                      FlipperPageCard(
                        child: Column(
                          children: [
                            _ConnectActionRow(
                              color: colors.accent,
                              onTap: onConnect,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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

class _ConnectActionRow extends StatelessWidget {
  const _ConnectActionRow({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: SizedBox(
                width: 44,
                height: 24,
                child: Row(
                  children: [
                    Icon(Icons.usb, size: 22, color: color),
                    const SizedBox(width: 2),
                    Icon(Icons.bluetooth, size: 20, color: color),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Connect',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
