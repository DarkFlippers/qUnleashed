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
  final (title, text) = describeConnectError(
    classifyConnectError(error),
    isBle: isBle,
  );
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

/// The title and body a [FlipperConnectErrorKind] is shown as.
///
/// Separate from the dialog so the mapping can be read without a widget tree.
/// It is the part worth testing: a kind that falls through to `unknown`, or
/// two kinds sharing one sentence, is a user told the wrong thing - and both
/// have happened here (#120).
@visibleForTesting
(String, String) describeConnectError(
  FlipperConnectErrorKind kind, {
  required bool isBle,
}) {
  final strings = l10n;
  switch (kind) {
    case FlipperConnectErrorKind.stalePairing:
      return (
        strings.connectStalePairingTitle,
        strings.connectStalePairingBody,
      );
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
    // Deliberately not folded into the case above. Both are "no room for
    // another one", and the sentence a user needs is different for each: that
    // one is fixed in the system Bluetooth settings, this one by letting go
    // of a link in the picker this dialog is sitting on top of. #120.
    case FlipperConnectErrorKind.sessionLimit:
      return (
        strings.connectSessionLimitTitle,
        strings.fmConnectSessionLimitBody(FlipperClient.maxSessions),
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
