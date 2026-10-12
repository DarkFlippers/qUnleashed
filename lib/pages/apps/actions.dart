import 'dart:async';

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

/// True from the moment a launch is asked for until the remote control has
/// been opened or the failure reported.
///
/// Process-wide, and not keyed on anything: [start] awaits `appStart` with a
/// 15-second timeout while the page stays fully interactive, and there is only
/// one screen to hand over. A second tap in that window started a second app
/// and pushed a second remote control - and `RemoteSession`'s constructor
/// starts the screen stream, so that is two concurrent screen streams on one
/// Flipper. Worse, the second `appStart` usually throws `AppSystemLocked`,
/// which is handled below by showing the busy dialog *and* opening the remote
/// control anyway.
///
/// A file-level variable rather than a field, because the three callers are
/// three different pages - the catalog, the app manager and the installer - and
/// the gesture is as wrong across two of them as it is twice on one. The engine
/// cannot hold it either: its per-alias `_actions` map serialises installs and
/// deletes, but `launchPath` goes straight to the client without touching it.
/// #244.
bool _handingOverScreen = false;

/// Runs [start] and hands the screen over to the remote control, which is where
/// a launched app shows up. A Flipper that is busy gets the dedicated dialog
/// instead of a raw error. Does nothing if a launch is already under way.
Future<void> launchApp(
  BuildContext context,
  Future<void> Function() start,
) async {
  if (_handingOverScreen) return;
  _handingOverScreen = true;
  try {
    await start();
    if (context.mounted) {
      unawaited(openRoute(context, AppRoute.remoteControl));
    }
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
  } finally {
    // Cleared even when the page has gone, so a launch started from a page the
    // user left cannot wedge the next one. The push above is deliberately not
    // awaited, so by here the remote control is on its way and the page that
    // asked is no longer the one on top.
    _handingOverScreen = false;
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
