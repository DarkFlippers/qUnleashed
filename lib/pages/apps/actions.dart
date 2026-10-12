import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../../components/dialogs/action.dart';
import '../../components/dialogs/confirm.dart';
import '../../components/navigation.dart';
import '../../components/notification.dart';
import '../../services/logging.dart';
import '../../theme/theme.dart';
import 'data/install_engine.dart';
import 'data/models/card.dart';
import 'data/models/category.dart';

/// The apps a launch has been asked for and not yet finished answering.
///
/// [start] awaits `appStart` with a 15-second timeout while the page stays
/// fully interactive, so a second tap in that window started the app again and
/// pushed a second remote control - and `RemoteSession`'s constructor starts
/// the screen stream, so that is two concurrent screen streams on one Flipper.
///
/// Keyed on the app, like the archive controller's own launch guard and for the
/// same reason: tapping Run on a *different* app is a thing a user does, and
/// the right answer to it is the busy dialog below, which offers to open the
/// remote control - not a dead button. Unkeyed, as the first draft had it, Run
/// was silently inert on three pages for up to fifteen seconds.
///
/// A file-level variable rather than a field, because the three callers are
/// three different pages - the catalog, the app manager and the installer - and
/// the gesture is as wrong across two of them as it is twice on one. The engine
/// cannot hold it either: its per-alias `_actions` map serialises installs and
/// deletes, but `launchPath` goes straight to the client without touching it.
/// #244.
final Set<String> _handingOverScreen = {};

/// Runs [start] and hands the screen over to the remote control, which is where
/// a launched app shows up. A Flipper that is busy gets the dedicated dialog
/// instead of a raw error.
///
/// [target] is what is being launched - an alias or a path - and a second call
/// naming the same one while the first is still out does nothing.
Future<void> launchApp(
  BuildContext context,
  Future<void> Function() start, {
  required String target,
}) async {
  if (!_handingOverScreen.add(target)) {
    // Not silence: a tap that does nothing is otherwise impossible to tell
    // from a tap that was never delivered, in a bug report or in a log.
    LogService.caught('[Apps] launch $target ignored, one already in flight');
    return;
  }
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
    _handingOverScreen.remove(target);
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
