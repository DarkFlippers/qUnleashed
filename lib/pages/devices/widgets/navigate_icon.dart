import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DeviceNavigateIcon extends StatelessWidget {
  const DeviceNavigateIcon({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 14,
        height: 14,
        child: SvgPicture.asset(
          'assets/ic/nav/navigate.svg',
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}
