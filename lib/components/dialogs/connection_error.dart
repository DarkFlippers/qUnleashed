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
/// Separate from the dialog because it has a second caller that is not one:
/// the device page's auto-connect hint, which has no gesture behind it and so
/// no dialog to put this in. Keeping the sentences in one place is the point -
/// a kind that falls through to `unknown`, or two kinds sharing one sentence,
/// is a user told the wrong thing, and both have happened here (#120).
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
    // Not folded into either neighbour, and the switch is exhaustive so the
    // compiler asked for this the moment the kind existed. The device
    // answered, so `deviceUnreachable`'s "move it closer" is wrong for a
    // Flipper sitting on the desk; the bond is intact, so `stalePairing`'s
    // "forget it" is premature. Both remedies appear here, cheapest first.
    // QUNLEASHED-Y.
    case FlipperConnectErrorKind.servicesMissing:
      return (
        strings.connectServicesMissingTitle,
        strings.connectServicesMissingBody,
      );
    // One body for both transports, where every other kind that needs a
    // transport has two. The fault is in the handset rather than in the link,
    // so there is nothing transport-specific to say - and the needle behind
    // this kind reads a Java throwable, which the Android *USB* path can
    // surface too. `connect_error.dart`'s `permission denied` comment is the
    // precedent: a sentence named for Bluetooth, reached from a cable, is the
    // collision to avoid.
    case FlipperConnectErrorKind.platformFault:
      return (
        strings.connectPlatformFaultTitle,
        strings.connectPlatformFaultBody,
      );
    case FlipperConnectErrorKind.unknown:
      return (
        strings.connectFailedTitle,
        isBle ? strings.connectFailedBleBody : strings.connectFailedUsbBody,
      );
  }
}
