import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'action.dart';

const String _kAsset = 'assets/pic/mifare/shrug-black.svg';
const Size _kAssetSize = Size(147.5, 95.8);

Future<void> showConnectionFailedDialog(
  BuildContext context,
  Object error, {
  required bool isBle,
}) {
  final (title, text) = _describe(classifyConnectError(error), isBle: isBle);
  return showDialog<void>(
    context: context,
    barrierColor: context.appColors.dialogBarrier,
    builder: (ctx) => FlipperActionDialog(
      imageAssetPath: _kAsset,
      imageSize: _kAssetSize,
      title: title,
      text: text,
      actionText: 'OK',
      onAction: () => Navigator.of(ctx).pop(),
    ),
  );
}

(String, String) _describe(FlipperConnectErrorKind kind, {required bool isBle}) {
  switch (kind) {
    case FlipperConnectErrorKind.stalePairing:
      return (
        'Pairing is out of date',
        'This Flipper is no longer paired correctly. Forget it in your system '
            'Bluetooth settings AND on the Flipper (Settings → Bluetooth → '
            'Forget all paired devices), then connect again.',
      );
    case FlipperConnectErrorKind.pairingIncomplete:
      return (
        'Pairing not completed',
        'Confirm the pairing request on the Flipper screen and enter the PIN it '
            'shows. If no request appeared, forget this Flipper in your system '
            'Bluetooth settings and try again.',
      );
    case FlipperConnectErrorKind.bluetoothUnavailable:
      return (
        'Bluetooth unavailable',
        'Turn Bluetooth on and allow this app to use it in your system '
            'settings, then connect again.',
      );
    case FlipperConnectErrorKind.tooManyDevices:
      return (
        'Too many paired devices',
        'Your system has reached its limit of paired Bluetooth devices. Forget '
            'a few unused devices in your Bluetooth settings, then connect '
            'again.',
      );
    case FlipperConnectErrorKind.busy:
      return (
        'Connection in progress',
        'A connection is already being established. Wait a moment, or turn '
            'Bluetooth off and on, then try again.',
      );
    case FlipperConnectErrorKind.deviceUnreachable:
      return (
        'Flipper not reachable',
        isBle
            ? 'The Flipper is out of range or its Bluetooth is off. Move it '
                  'closer and enable Bluetooth in the Flipper system menu, then '
                  'connect again.'
            : 'The device did not respond. Unplug it and plug it back in, then '
                  'connect again.',
      );
    case FlipperConnectErrorKind.unknown:
      return (
        'Connection failed',
        isBle
            ? 'Turn Bluetooth off and on in the Flipper Zero system menu, then '
                  'connect again. Restart the app only if that does not help.'
            : 'Unplug the device and plug it back in, then connect again. '
                  'Restart the app only if that does not help.',
      );
  }
}
