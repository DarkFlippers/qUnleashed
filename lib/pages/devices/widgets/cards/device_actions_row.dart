import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../theme/theme.dart';

class DeviceActionsRow extends StatelessWidget {
  const DeviceActionsRow({
    super.key,
    required this.isBle,
    required this.onDisconnect,
    required this.onPlayAlert,
    required this.onReboot,
  });

  static const double _spacing = 10;
  static const double _iconSize = 26;
  static const double _contentSpacing = 10;
  static const double _minWideButtonWidth = 170;

  final bool isBle;
  final VoidCallback onDisconnect;
  final VoidCallback? onPlayAlert;
  final VoidCallback onReboot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        const buttonCount = 3;
        final buttonWidth =
            (constraints.maxWidth - _spacing * (buttonCount - 1)) / buttonCount;
        final horizontal = buttonWidth >= _minWideButtonWidth;
        final buttonHeight = horizontal ? 72.0 : buttonWidth;

        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: buttonHeight,
                child: _DeviceActionButton(
                  icon: isBle ? Icons.bluetooth_disabled : Icons.usb_off,
                  label: 'Disconnect',
                  iconColor: colors.accent,
                  textColor: colors.textPrimary,
                  horizontal: horizontal,
                  onTap: onDisconnect,
                ),
              ),
            ),
            const SizedBox(width: _spacing),
            Expanded(
              child: SizedBox(
                height: buttonHeight,
                child: _DeviceActionButton(
                  iconAsset: 'assets/ic/device/ring.svg',
                  label: 'Play Alert',
                  iconColor: onPlayAlert == null
                      ? colors.textMuted
                      : colors.accent,
                  textColor: onPlayAlert == null
                      ? colors.textMuted
                      : colors.textPrimary,
                  horizontal: horizontal,
                  onTap: onPlayAlert,
                ),
              ),
            ),
            const SizedBox(width: _spacing),
            Expanded(
              child: SizedBox(
                height: buttonHeight,
                child: _DeviceActionButton(
                  iconAsset: 'assets/ic/device/syncing.svg',
                  label: 'Reboot',
                  iconColor: colors.accent,
                  textColor: colors.textPrimary,
                  horizontal: horizontal,
                  onTap: onReboot,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeviceActionButton extends StatelessWidget {
  const _DeviceActionButton({
    this.iconAsset,
    this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    required this.horizontal,
    required this.onTap,
  }) : assert(iconAsset != null || icon != null);

  final String? iconAsset;
  final IconData? icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final bool horizontal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          excludeSemantics: true,
          child: Center(
            child: horizontal
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIcon(),
                      const SizedBox(width: DeviceActionsRow._contentSpacing),
                      _buildLabel(maxLines: 1),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIcon(),
                      const SizedBox(height: DeviceActionsRow._contentSpacing),
                      _buildLabel(maxLines: 2),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return SizedBox(
      width: DeviceActionsRow._iconSize,
      height: DeviceActionsRow._iconSize,
      child: iconAsset != null
          ? SvgPicture.asset(
              iconAsset!,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            )
          : Icon(icon, size: DeviceActionsRow._iconSize, color: iconColor),
    );
  }

  Widget _buildLabel({required int maxLines}) {
    return Text(
      label,
      maxLines: maxLines,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
