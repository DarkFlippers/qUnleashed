import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../../components/dialogs/action.dart';
import '../../components/dialogs/confirm.dart';
import '../../components/navigation.dart';
import '../../components/notification.dart';
import '../../theme/theme.dart';
import 'data/install_engine.dart';
import 'data/models/card.dart';
import 'data/models/category.dart';

/// Runs [start] and hands the screen over to the remote control, which is where
/// a launched app shows up. A Flipper that is busy gets the dedicated dialog
/// instead of a raw error.
Future<void> launchApp(
  BuildContext context,
  Future<void> Function() start,
) async {
  try {
    await start();
    if (context.mounted) openRoute(context, AppRoute.remoteControl);
  } catch (e) {
    if (!context.mounted) return;
    if (e is FlipperRpcAppSystemLockedException) {
      await showDialog<void>(
        context: context,
        barrierColor: context.appColors.dialogBarrier,
        builder: (dialogContext) => FlipperActionDialog(
          imageAssetPath: kFlipperBusyAssetPath,
          title: kFlipperBusyTitle,
          text: kFlipperBusyMessage,
          actionText: kFlipperBusyAction,
          onAction: () {
            Navigator.of(dialogContext).pop();
            openRoute(context, AppRoute.remoteControl);
          },
        ),
      );
      return;
    }
    context.showNotification(
      context.l10n.appOpenFailed('$e'),
      type: QNotificationType.error,
    );
  }
}

Future<void> confirmDeleteApp(
  BuildContext context, {
  required InstallEngine engine,
  required AppCard app,
  AppCategory? category,
}) async {
  final ok = await QConfirmDialog.show(
    context,
    title: context.l10n.appDeleteTitle,
    message: context.l10n.appDeleteMessage(app.name),
    confirmLabel: context.l10n.commonDelete,
  );
  if (ok) await engine.uninstall(app, category: category);
}
