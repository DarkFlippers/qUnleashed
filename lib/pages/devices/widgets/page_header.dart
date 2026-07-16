import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'flipper_mockup.dart';

class DevicePageHeader extends StatelessWidget {
  const DevicePageHeader({
    super.key,
    required this.topInset,
    required this.headerHeight,
    required this.title,
    required this.subtitle,
    required this.active,
    this.dfu = false,
    this.virtual = false,
    this.infoEntries = const [],
    this.deviceInfo = const {},
    this.connectionLabel = 'USB',
    this.connectionIcon = Icons.usb,
    this.onOpenFullInfo,
  });

  final double topInset;
  final double headerHeight;
  final String title;
  final String subtitle;
  final bool active;
  final bool dfu;
  final bool virtual;
  final List<MapEntry<String, String>> infoEntries;
  final Map<String, String> deviceInfo;
  final String connectionLabel;
  final IconData connectionIcon;
  final VoidCallback? onOpenFullInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: colors.accent,
        padding: EdgeInsets.only(top: topInset),
        height: headerHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            if (wide && infoEntries.isNotEmpty) {
              return Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: FlipperMockupHero(
                        active: active,
                        dfu: dfu,
                        virtual: virtual,
                        title: title,
                        infoEntries: infoEntries,
                        deviceInfo: deviceInfo,
                        connectionLabel: connectionLabel,
                        connectionIcon: connectionIcon,
                      ),
                    ),
                  ),
                  if (onOpenFullInfo != null)
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: TextButton.icon(
                        onPressed: onOpenFullInfo,
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: const Text('Full Info'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onAccent,
                          fixedSize: const Size.fromHeight(36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: colors.onAccent.withValues(alpha: .28),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
                  child: SizedBox(
                    height: 100,
                    child: FlipperMockupWidget(
                      active: active,
                      dfu: dfu,
                      virtual: virtual,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onAccent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: colors.onAccent),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
