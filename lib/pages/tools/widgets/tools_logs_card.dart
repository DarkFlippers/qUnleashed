import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../../../widgets/device_shell.dart';

class ToolsLogsCard extends StatelessWidget {
  const ToolsLogsCard({
    super.key,
    required this.iconColor,
    required this.onTap,
  });

  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FlipperActionRow(
      iconAsset: 'assets/flipper_svg/info/ic_options.svg',
      label: 'Logs',
      color: iconColor,
      trailing: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: SvgPicture.asset(
            'assets/flipper_svg/core/ic_navigate.svg',
            colorFilter: ColorFilter.mode(colors.textMuted, BlendMode.srcIn),
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}
