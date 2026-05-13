import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../pages/remote/page.dart';
import '../theme.dart';

const Color _kFlipperScreenInk = Colors.black;

const String kFlipperBusyTitle = 'Flipper is Busy';
const String kFlipperBusyMessage =
    'Exit the current app on Flipper to use this feature';
const String kFlipperBusyAction = 'Remoute control';
const String kFlipperBusyAssetPath =
    'assets/flipper_svg/core/pic_flipper_is_busy.svg';
const double _kFlipperBusyDialogWidth = 268;
const double _kFlipperBusyOuterPadding = 16;
const double _kFlipperBusyScreenPadding = 4;
const double _kFlipperBusyAssetAspectRatio = 200 / 84;
const double _kFlipperBusyScreenWidth =
    _kFlipperBusyDialogWidth - (_kFlipperBusyOuterPadding * 2);
const double _kFlipperBusyImageWidth =
    _kFlipperBusyScreenWidth - (_kFlipperBusyScreenPadding * 2);
const double _kFlipperBusyImageHeight =
    _kFlipperBusyImageWidth / _kFlipperBusyAssetAspectRatio;

Future<void>? _flipperBusyDialogFuture;

Future<void> showFlipperBusyDialog(
  BuildContext context, {
  VoidCallback? onOk,
}) {
  final activeDialog = _flipperBusyDialogFuture;
  if (activeDialog != null) return activeDialog;

  final colors = context.appColors;
  final action = onOk ??
      () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RemoteControlPage()),
        );
      };

  late final Future<void> dialogFuture;
  dialogFuture = showDialog<void>(
    context: context,
    barrierColor: colors.dialogBarrier,
    builder: (dialogContext) {
      return FlipperBusyDialog(
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onOk: action,
      );
    },
  ).whenComplete(() {
    if (identical(_flipperBusyDialogFuture, dialogFuture)) {
      _flipperBusyDialogFuture = null;
    }
  });
  _flipperBusyDialogFuture = dialogFuture;
  return dialogFuture;
}

class FlipperBusyDialog extends StatelessWidget {
  const FlipperBusyDialog({
    super.key,
    required this.onDismiss,
    this.onOk,
  });

  final VoidCallback onDismiss;
  final VoidCallback? onOk;

  void _handleOk() {
    onDismiss();
    onOk?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: colors.dialogBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _kFlipperBusyDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                _kFlipperBusyOuterPadding,
                _kFlipperBusyOuterPadding,
                _kFlipperBusyOuterPadding,
                0,
              ),
              child: _FlipperBusyScreenShell(),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 24, left: 12, right: 12),
              child: Text(
                kFlipperBusyTitle,
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
              padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
              child: Text(
                kFlipperBusyMessage,
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
                  onPressed: _handleOk,
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
                  child: const Text(kFlipperBusyAction),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlipperBusyScreenShell extends StatelessWidget {
  const _FlipperBusyScreenShell();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.screenBorder, width: 3),
        borderRadius: BorderRadius.circular(16),
        color: colors.screenBackground,
      ),
      padding: const EdgeInsets.all(_kFlipperBusyScreenPadding),
      child: SizedBox(
        width: _kFlipperBusyImageWidth,
        height: _kFlipperBusyImageHeight,
        child: SvgPicture.asset(
          kFlipperBusyAssetPath,
          fit: BoxFit.fill,
          colorFilter: const ColorFilter.mode(
            _kFlipperScreenInk,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
