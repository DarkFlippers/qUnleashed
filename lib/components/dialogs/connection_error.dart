import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';
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

(String, String) _describe(
  FlipperConnectErrorKind kind, {
  required bool isBle,
}) {
  final strings = l10n;
  switch (kind) {
    case FlipperConnectErrorKind.stalePairing:
      return (strings.connectStalePairingTitle, strings.connectStalePairingBody);
    case FlipperConnectErrorKind.pairingIncomplete:
      return (
        strings.connectPairingIncompleteTitle,
        strings.connectPairingIncompleteBody,
      );
    case FlipperConnectErrorKind.bluetoothUnavailable:
      return (
        strings.connectBluetoothUnavailableTitle,
        strings.connectBluetoothUnavailableBody,
      );
    case FlipperConnectErrorKind.tooManyDevices:
      return (
        strings.connectTooManyDevicesTitle,
        strings.connectTooManyDevicesBody,
      );
    case FlipperConnectErrorKind.busy:
      return (strings.connectBusyTitle, strings.connectBusyBody);
    case FlipperConnectErrorKind.deviceUnreachable:
      return (
        strings.connectUnreachableTitle,
        isBle
            ? strings.connectUnreachableBleBody
            : strings.connectUnreachableUsbBody,
      );
    case FlipperConnectErrorKind.unknown:
      return (
        strings.connectFailedTitle,
        isBle ? strings.connectFailedBleBody : strings.connectFailedUsbBody,
      );
  }
}
