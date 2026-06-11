import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

const Color _kFlipperScreenInk = Colors.black;

const double _kDialogWidth = 268;
const double _kOuterPadding = 16;
const double _kScreenPadding = 4;
const double _kAssetAspectRatio = 200 / 84;
const double _kScreenWidth = _kDialogWidth - (_kOuterPadding * 2);
const double _kImageWidth = _kScreenWidth - (_kScreenPadding * 2);
const double _kImageHeight = _kImageWidth / _kAssetAspectRatio;

const String kFlipperBusyTitle = 'Flipper is Busy';
const String kFlipperBusyMessage =
    'Exit the current app on Flipper to use this feature';
const String kFlipperBusyAction = 'Remoute control';
const String kFlipperBusyAssetPath = 'assets/pic/status/busy.svg';

const String kCliBluetoothUnavailableTitle = 'Terminal Unavailable';
const String kCliBluetoothUnavailableMessage =
    'Terminal session is not available over Bluetooth.';
const String kCliBluetoothUnavailableAction = 'Disconnect and continue';
const String kCliBluetoothUnavailableAssetPath = 'assets/pic/status/busy.svg';

class FlipperActionDialog extends StatelessWidget {
  const FlipperActionDialog({
    super.key,
    required this.imageAssetPath,
    this.imageSize = const Size(_kImageWidth, _kImageHeight),
    this.title,
    required this.text,
    required this.actionText,
    required this.onAction,
  });

  final String imageAssetPath;
  final Size imageSize;
  final String? title;
  final String text;
  final String actionText;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: colors.dialogBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _kDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kOuterPadding,
                _kOuterPadding,
                _kOuterPadding,
                0,
              ),
              child: _FlipperScreenShell(
                imageAssetPath: imageAssetPath,
                imageSize: imageSize,
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(top: 24, left: 12, right: 12),
                child: Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.dialogText,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(
                top: title == null ? 24 : 4,
                left: 12,
                right: 12,
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.dialogMuted,
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(actionText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlipperScreenShell extends StatelessWidget {
  const _FlipperScreenShell({
    required this.imageAssetPath,
    required this.imageSize,
  });

  final String imageAssetPath;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.screenBorder, width: 3),
        borderRadius: BorderRadius.circular(16),
        color: colors.screenBackground,
      ),
      padding: const EdgeInsets.all(_kScreenPadding),
      child: SizedBox(
        width: _kImageWidth,
        height: _kImageHeight,
        child: Center(
          child: SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: SvgPicture.asset(
              imageAssetPath,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                _kFlipperScreenInk,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
