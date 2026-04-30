import 'package:flutter/material.dart';

import '../theme.dart';
import 'device_shell.dart';

class DevicePageHeader extends StatelessWidget {
  const DevicePageHeader({
    super.key,
    required this.topInset,
    required this.headerHeight,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final double topInset;
  final double headerHeight;
  final String title;
  final String subtitle;
  final bool active;

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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
              child: SizedBox(
                height: 100,
                child: FlipperMockupWidget(active: active),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
