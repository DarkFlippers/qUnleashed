import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../apps_install_service.dart';
import '../models/app_card.dart';
import '../models/app_category.dart';
import '../models/app_detail.dart';

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
        primary: _ProgressButton(
          progress: action.progress,
          type: action.type,
          size: size,
        ),
      );
    }

    if (!service.isReady) {
      return _ActionRow(
        size: size,
        primary: _Pill(
          label: 'INSTALL',
          background: colors.accent,
          foreground: colors.onAccent,
          size: size,
          onTap: () => _connectHint(context),
        ),
      );
    }

    switch (state) {
      case AppButtonState.install:
        return _ActionRow(
          size: size,
          primary: _Pill(
            label: 'INSTALL',
            background: colors.accent,
            foreground: colors.onAccent,
            size: size,
            onTap: () => service.installOrUpdate(app, category: category, detail: detail),
          ),
        );
      case AppButtonState.update:
        return _ActionRow(
          size: size,
          primary: _Pill(
            label: 'UPDATE',
            background: colors.success,
            foreground: colors.onAccent,
            size: size,
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
          primary: _Pill(
            label: 'BUILT-IN',
            background: colors.success,
            foreground: colors.onAccent,
            size: size,
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
          primary: _Pill(
            label: 'OPEN',
            background: Colors.transparent,
            foreground: colors.textPrimary,
            size: size,
            border: BorderSide(color: colors.divider, width: 1.5),
            onTap: () async {
              try {
                await service.launch(app, category: category);
                onLaunched?.call();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Open failed: $e')),
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
          primary: _Pill(
            label: 'N/A',
            background: colors.divider,
            foreground: colors.textMuted,
            size: size,
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
          primary: _ProgressButton(progress: 0, type: AppActionType.install, size: size),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
    }
  }

  void _connectHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connect Flipper to install apps')),
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    required this.size,
    this.onTap,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final BorderSide? border;
  final AppActionButtonSize size;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == AppActionButtonSize.large;
    final radius = BorderRadius.circular(isLarge ? 10 : 8);
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        side: border ?? BorderSide.none,
        borderRadius: radius,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: isLarge ? 48 : 32,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: isLarge ? 24 : 12),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: isLarge ? 14 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressButton extends StatelessWidget {
  const _ProgressButton({required this.progress, required this.type, required this.size});

  final double progress;
  final AppActionType type;
  final AppActionButtonSize size;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == AppActionButtonSize.large;
    final state = _ProgressState.resolve(type);
    final borderColor = state.color;
    final baseColor = state.color.withValues(alpha: 0.18);
    final progressValue = progress.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(isLarge ? 10 : 8);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: isLarge ? 48 : 32,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: baseColor,
                  border: Border.all(color: borderColor, width: 1.25),
                  borderRadius: radius,
                ),
              ),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: constraints.maxWidth * progressValue,
                      height: constraints.maxHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: state.color,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 1.25),
                  borderRadius: radius,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isLarge ? 12 : 8),
              child: Text(
                '${state.label} ${(progressValue * 100).round()}%',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLarge ? 14 : 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
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

  static _ProgressState resolve(AppActionType type) {
    return switch (type) {
      AppActionType.update => _ProgressState(
          label: 'UPDATE',
          color: FlipperOriginalColors.green,
        ),
      AppActionType.delete => _ProgressState(
          label: 'DELETE',
          color: FlipperOriginalColors.danger,
        ),
      AppActionType.install => _ProgressState(
          label: 'INSTALL',
          color: FlipperOriginalColors.accent,
        ),
    };
  }
}
