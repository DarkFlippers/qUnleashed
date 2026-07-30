import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../../../components/dialogs/action.dart';
import '../../../../components/dialogs/confirm.dart';
import '../../../../widgets/notification.dart';
import '../../../../widgets/progress_button.dart';
import '../../../tools/remote/desktop/page.dart';
import '../../data/catalog_state.dart';
import '../../data/install_engine.dart';
import '../../data/models/card.dart';
import '../../data/models/category.dart';
import '../../data/models/detail.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.engine,
    required this.state,
    required this.app,
    this.category,
    this.detail,
    this.onLaunched,
    this.size = AppActionButtonSize.compact,
  });

  final InstallEngine engine;
  final CatalogAppState state;
  final AppCard app;
  final AppCategory? category;
  final AppDetail? detail;
  final VoidCallback? onLaunched;
  final AppActionButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final action = engine.actionFor(app);

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

    if (!engine.isReady) {
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
      case CatalogAppState.install:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'INSTALL',
            color: colors.accent,
            onTap: () =>
                engine.installOrUpdate(app, category: category, detail: detail),
          ),
        );
      case CatalogAppState.update:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'UPDATE',
            color: colors.success,
            onTap: () =>
                engine.installOrUpdate(app, category: category, detail: detail),
          ),
          secondary: _DeleteButton(size: size, onTap: () => _confirmDelete(context)),
        );
      case CatalogAppState.open:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: 'OPEN',
            color: colors.accent,
            onTap: () => _launchApp(context),
          ),
          secondary: _DeleteButton(size: size, onTap: () => _confirmDelete(context)),
        );
    }
  }

  Widget _buildProgressButton({
    required AppActionType type,
    required AppActionStage stage,
    required double progress,
  }) {
    final progressState = _ProgressState.resolve(type, stage);
    final isLarge = size == AppActionButtonSize.large;
    final indeterminate = stage == AppActionStage.queued ||
        stage == AppActionStage.check ||
        type == AppActionType.delete;
    return ProgressButton(
      text: progressState.label,
      color: progressState.color,
      progress: indeterminate ? null : progress,
      indeterminate: indeterminate,
      showPercent: !indeterminate,
      height: isLarge ? 48 : 32,
      borderRadius: isLarge ? 10 : 8,
      horizontalPadding: isLarge ? 12 : 8,
      textStyle: ProgressButton.defaultTextStyle.copyWith(
        fontSize: isLarge ? 40 : 20,
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isLarge = size == AppActionButtonSize.large;
    return ProgressButton(
      text: label,
      color: color,
      onPressed: onTap,
      height: isLarge ? 48 : 32,
      borderRadius: isLarge ? 10 : 8,
      horizontalPadding: isLarge ? 24 : 12,
      textStyle: ProgressButton.defaultTextStyle.copyWith(
        fontSize: isLarge ? 40 : 20,
      ),
    );
  }

  void _connectHint(BuildContext context) {
    context.showNotification(
      'Connect a device to install apps',
      type: QNotificationType.warning,
    );
  }

  Future<void> _launchApp(BuildContext context) async {
    try {
      await engine.launch(app, category: category);
      onLaunched?.call();
    } catch (e) {
      if (!context.mounted) return;
      final colors = context.appColors;
      if (e is FlipperRpcAppSystemLockedException) {
        await showDialog<void>(
          context: context,
          barrierColor: colors.dialogBarrier,
          builder: (dialogContext) => FlipperActionDialog(
            imageAssetPath: kFlipperBusyAssetPath,
            title: kFlipperBusyTitle,
            text: kFlipperBusyMessage,
            actionText: kFlipperBusyAction,
            onAction: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemoteControlPage()),
              );
            },
          ),
        );
        return;
      }
      context.showNotification('Open failed: $e', type: QNotificationType.error);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await QConfirmDialog.show(
      context,
      title: 'Delete app?',
      message: 'Remove "${app.name}" from your device?',
      confirmLabel: 'Delete',
    );
    if (ok) {
      await engine.uninstall(app, category: category);
    }
  }
}

enum AppActionButtonSize { compact, large }

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.size, required this.primary, this.secondary});

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
    final color = switch (type) {
      AppActionType.update => FlipperOriginalColors.green,
      AppActionType.delete => FlipperOriginalColors.danger,
      AppActionType.install => FlipperOriginalColors.accent,
    };
    if (stage == AppActionStage.queued) {
      return _ProgressState(label: 'QUEUED', color: color);
    }
    if (stage == AppActionStage.check) {
      return _ProgressState(label: 'CHECK', color: color);
    }
    if (type == AppActionType.delete) {
      return _ProgressState(label: 'DELETE', color: color);
    }
    return _ProgressState(
      label: stage == AppActionStage.upload ? 'UPLOAD' : 'DOWNLOAD',
      color: color,
    );
  }
}
