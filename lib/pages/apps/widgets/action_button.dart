import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/flipper_action_dialog.dart';
import '../../../widgets/notification.dart';
import '../../../widgets/progress_button.dart';
import '../../remote/page.dart';
import '../install_service.dart';
import '../models/card.dart';
import '../models/category.dart';
import '../models/detail.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.service,
    required this.app,
    this.category,
    this.detail,
    this.onLaunched,
    this.size = AppActionButtonSize.compact,
  });

  final AppsInstallService service;
  final AppCard app;
  final AppCategory? category;
  final AppDetail? detail;
  final VoidCallback? onLaunched;
  final AppActionButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = service.buttonState(app);
    final action = service.actionFor(app);

    if (action != null) {
      return _ActionRow(
        size: size,
        primary: _buildProgressButton(
          type: action.type,
          stage: action.stage,
          progress: action.progress,
        ),
      );
    }

    if (!service.isReady) {
      return _ActionRow(
        size: size,
        primary: _buildButton(
          label: 'INSTALL',
          color: colors.accent,
          onTap: () => _connectHint(context),
        ),
      );
    }

    switch (state) {
      case AppButtonState.install:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'INSTALL',
            color: colors.accent,
            onTap: () => service.installOrUpdate(app, category: category, detail: detail),
          ),
        );
      case AppButtonState.update:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'UPDATE',
            color: colors.success,
            onTap: () => service.installOrUpdate(app, category: category, detail: detail),
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
      case AppButtonState.preinstalled:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'BUILT-IN',
            color: colors.success,
            onTap: () => service.installOrUpdate(app, category: category, detail: detail),
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
      case AppButtonState.installed:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'OPEN',
            color: colors.accent,
            onTap: () async {
              try {
                await service.launch(app, category: category);
                onLaunched?.call();
              } catch (e) {
                if (!context.mounted) return;
                if (e is FlipperRpcAppSystemLockedException) {
                  await showDialog<void>(
                    context: context,
                    barrierColor: colors.dialogBarrier,
                    builder: (dialogContext) {
                      return FlipperActionDialog(
                        imageAssetPath: kFlipperBusyAssetPath,
                        title: kFlipperBusyTitle,
                        text: kFlipperBusyMessage,
                        actionText: kFlipperBusyAction,
                        onAction: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RemoteControlPage(),
                            ),
                          );
                        },
                      );
                    },
                  );
                  return;
                }
                context.showNotification(
                  'Open failed: $e',
                  type: QNotificationType.error,
                );
              }
            },
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
      case AppButtonState.unsupported:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'N/A',
            color: colors.divider,
            onTap: null,
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
      case AppButtonState.inProgress:
        return _ActionRow(
          size: size,
          primary: _buildProgressButton(
            type: AppActionType.install,
            stage: AppActionStage.download,
            progress: 0,
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
    }
  }

  Widget _buildProgressButton({
    required AppActionType type,
    required AppActionStage stage,
    required double progress,
  }) {
    final progressState = _ProgressState.resolve(type, stage);
    return ProgressButton(
      text: progressState.label,
      color: progressState.color,
      progress: progress,
      showPercent: true,
    );
  }

  Widget _buildButton({
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return ProgressButton(
      text: label,
      color: color,
      progress: double.nan,
      onPressed: onTap,
    );
  }

  void _connectHint(BuildContext context) {
    context.showNotification(
      'Connect Flipper to install apps',
      type: QNotificationType.warning,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.appColors;
        return AlertDialog(
          backgroundColor: colors.dialogBackground,
          title: Text('Delete app?', style: TextStyle(color: colors.dialogText)),
          content: Text(
            'Remove "${app.name}" from your Flipper?',
            style: TextStyle(color: colors.dialogText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.dialogMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete', style: TextStyle(color: colors.danger)),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await service.uninstall(app, category: category);
    }
  }
}

enum AppActionButtonSize { compact, large }

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.size,
    required this.primary,
    this.secondary,
  });

  final AppActionButtonSize size;
  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == AppActionButtonSize.large;
    if (secondary == null) {
      if (isLarge) return primary;
      return SizedBox(width: 92, child: primary);
    }
    return Row(
      mainAxisSize: isLarge ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (isLarge)
          Expanded(child: primary)
        else
          SizedBox(width: 92, child: primary),
        SizedBox(width: isLarge ? 12 : 8),
        secondary!,
      ],
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap, required this.size});

  final VoidCallback onTap;
  final AppActionButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLarge = size == AppActionButtonSize.large;
    final dim = isLarge ? 46.0 : 34.0;
    final radius = BorderRadius.circular(isLarge ? 10 : 8);

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.divider, width: 1.25),
        borderRadius: radius,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          width: dim,
          height: dim,
          child: Icon(
            Icons.delete_outline,
            color: colors.danger,
            size: isLarge ? 22 : 18,
          ),
        ),
      ),
    );
  }
}

class _ProgressState {
  const _ProgressState({required this.label, required this.color});

  final String label;
  final Color color;

  static _ProgressState resolve(AppActionType type, AppActionStage stage) {
    if (stage == AppActionStage.upload) {
      return _ProgressState(
        label: 'UPLOAD',
        color: switch (type) {
          AppActionType.update => FlipperOriginalColors.green,
          AppActionType.delete => FlipperOriginalColors.danger,
          AppActionType.install => FlipperOriginalColors.accent,
        },
      );
    }
    return switch (type) {
      AppActionType.update => _ProgressState(
          label: 'DOWNLOAD',
          color: FlipperOriginalColors.green,
        ),
      AppActionType.delete => _ProgressState(
          label: 'DOWNLOAD',
          color: FlipperOriginalColors.danger,
        ),
      AppActionType.install => _ProgressState(
          label: 'DOWNLOAD',
          color: FlipperOriginalColors.accent,
        ),
    };
  }
}
