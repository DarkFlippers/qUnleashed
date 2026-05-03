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
      return _ProgressPill(
        progress: action.progress,
        type: action.type,
        size: size,
      );
    }

    if (!service.isReady) {
      return _Pill(
        label: 'INSTALL',
        background: colors.accent,
        foreground: colors.onAccent,
        size: size,
        onTap: () => _connectHint(context),
      );
    }

    switch (state) {
      case AppButtonState.install:
        return _Pill(
          label: 'INSTALL',
          background: colors.accent,
          foreground: colors.onAccent,
          size: size,
          onTap: () => service.installOrUpdate(app, category: category, detail: detail),
        );
      case AppButtonState.update:
        return _Pill(
          label: 'UPDATE',
          background: colors.success,
          foreground: colors.onAccent,
          size: size,
          onTap: () => service.installOrUpdate(app, category: category, detail: detail),
        );
      case AppButtonState.installed:
        return _Pill(
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
        );
      case AppButtonState.unsupported:
        return _Pill(
          label: 'N/A',
          background: colors.divider,
          foreground: colors.textMuted,
          size: size,
          onTap: null,
        );
      case AppButtonState.inProgress:
        return _ProgressPill(progress: 0, type: AppActionType.install, size: size);
    }
  }

  void _connectHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connect Flipper to install apps')),
    );
  }
}

enum AppActionButtonSize { compact, large }

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

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.progress, required this.type, required this.size});

  final double progress;
  final AppActionType type;
  final AppActionButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLarge = size == AppActionButtonSize.large;
    final color = switch (type) {
      AppActionType.update => colors.success,
      AppActionType.delete => colors.danger,
      AppActionType.install => colors.accent,
    };
    final dim = isLarge ? 48.0 : 32.0;
    return SizedBox(
      width: dim,
      height: dim,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: dim,
            height: dim,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              color: color,
              backgroundColor: colors.divider,
            ),
          ),
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(
              fontSize: isLarge ? 11 : 9,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
