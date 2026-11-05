import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../../../components/notification.dart';
import '../../../../components/progress_button.dart';
import '../../actions.dart';
import '../../data/artifact_signature.dart';
import '../../data/catalog_api.dart' show CatalogFamily;
import '../../data/catalog_state.dart';
import '../../data/install_engine.dart';
import '../../data/models/card.dart';
import '../../data/models/category.dart';
import '../../data/models/detail.dart';
import '../../../../services/logging.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.engine,
    required this.state,
    required this.app,
    this.category,
    this.detail,
    this.size = AppActionButtonSize.compact,
    this.family = CatalogFamily.apps,
  });

  final InstallEngine engine;
  final CatalogAppState state;
  final AppCard app;
  final AppCategory? category;
  final AppDetail? detail;
  final AppActionButtonSize size;
  final CatalogFamily family;

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
          cancelling: engine.isCancelling(app.alias),
        ),
      );
    }

    if (family == CatalogFamily.animations) {
      final installed = engine.isReady && state != CatalogAppState.install;
      return _ActionRow(
        size: size,
        primary: _buildButton(
          label: !engine.isReady
              ? l10n.appActionDownload
              : installed
              ? l10n.appActionUpdate
              : l10n.appActionInstall,
          color: installed ? colors.success : colors.accent,
          onTap: () => _installAnimation(context),
        ),
      );
    }

    if (!engine.isReady) {
      final api = _downloadApi;
      return _ActionRow(
        size: size,
        primary: _buildButton(
          label: l10n.appActionInstall,
          color: colors.accent,
          onTap: () => _connectHint(context),
        ),
        secondary: api == null
            ? null
            : _DownloadButton(onTap: () => _download(context, api)),
      );
    }

    if (family == CatalogFamily.menuStyles) {
      return _ActionRow(
        size: size,
        primary: switch (state) {
          CatalogAppState.install => _buildButton(
            label: l10n.appActionInstall,
            color: colors.accent,
            onTap: () => _installMenuStyle(context),
          ),
          CatalogAppState.update => _buildButton(
            label: l10n.appActionUpdate,
            color: colors.success,
            onTap: () => _installMenuStyle(context),
          ),
          CatalogAppState.open => _buildButton(
            label: l10n.appActionInstalled,
            color: colors.textMuted,
          ),
        },
      );
    }

    switch (state) {
      case CatalogAppState.install:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: l10n.appActionInstall,
            color: colors.accent,
            onTap: () => _install(context),
          ),
        );
      case CatalogAppState.update:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: l10n.appActionUpdate,
            color: colors.success,
            onTap: () => _install(context),
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
      // A terminal command has nothing to open: it runs from the CLI.
      case CatalogAppState.open when family == CatalogFamily.cli:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: l10n.appActionInstalled,
            color: colors.textMuted,
          ),
          secondary: _DeleteButton(
            size: size,
            onTap: () => _confirmDelete(context),
          ),
        );
      case CatalogAppState.open:
        return _ActionRow(
          size: size,
          primary: _buildButton(
            label: l10n.appActionOpen,
            color: colors.accent,
            onTap: () => _launchApp(context),
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
    required bool cancelling,
  }) {
    final progressState = _ProgressState.resolve(type, stage, cancelling);
    final isLarge = size == AppActionButtonSize.large;
    final indeterminate =
        cancelling ||
        stage == AppActionStage.queued ||
        stage == AppActionStage.check ||
        stage == AppActionStage.build ||
        type == AppActionType.delete;
    return ProgressButton(
      text: progressState.label,
      color: progressState.color,
      onPressed: cancelling ? null : () => engine.cancel(app.alias),
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

  /// The api of the build a download would fetch: on an app's own page, for
  /// a family that is built, when one is ready. Null hides the button.
  String? get _downloadApi {
    if (size != AppActionButtonSize.large) return null;
    if (family == CatalogFamily.animations) return null;
    final version = detail?.card.currentVersion ?? app.currentVersion;
    if (version == null || version.id.isEmpty) return null;
    final api = version.currentBuild?.sdk?.api ?? '';
    return api.isEmpty ? null : api;
  }

  /// Saves the build to this phone or computer, for a Flipper that is not
  /// here: the server names the file, the browser keeps it.
  Future<void> _download(BuildContext context, String api) async {
    final version = detail?.card.currentVersion ?? app.currentVersion;
    final uri = engine.api.buildDownloadUri(
      version!.id,
      api: api,
      target: engine.api.target ?? 'f7',
      family: family,
    );
    var started = false;
    try {
      started = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      LogService.warn('[AppAction] download of ${app.alias} failed: $e');
    }
    if (started || !context.mounted) return;
    context.showNotification(
      context.l10n.appDownloadFailed,
      type: QNotificationType.warning,
    );
  }

  void _connectHint(BuildContext context) {
    context.showNotification(
      context.l10n.catalogConnectToInstall,
      type: QNotificationType.warning,
    );
  }

  Future<void> _installMenuStyle(BuildContext context) async {
    final ok = await engine.installMenuStyle(app);
    if (!context.mounted) return;
    if (!ok) {
      _reportFailure(context);
      return;
    }
    context.showNotification(
      context.l10n.menuStyleInstalledHint,
      type: QNotificationType.good,
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _install(BuildContext context) async {
    final ok = await engine.installOrUpdate(
      app,
      category: category,
      detail: detail,
    );
    if (!context.mounted) return;
    if (!ok) {
      _reportFailure(context);
    } else if (family == CatalogFamily.cli) {
      context.showNotification(
        context.l10n.cliInstalledHint,
        type: QNotificationType.good,
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _installAnimation(BuildContext context) async {
    final toLibrary = !engine.isReady;
    final ok = await engine.installAnimation(app);
    if (!context.mounted) return;
    if (!ok) {
      _reportFailure(context);
      return;
    }
    if (toLibrary) {
      context.showNotification(
        context.l10n.paintSaved(app.name),
        type: QNotificationType.good,
      );
    }
  }

  void _reportFailure(BuildContext context) {
    final failure = engine.takeFailure(app.alias);
    if (failure is! ArtifactSignatureException) return;
    context.showNotification(
      failure.unknownKey
          ? context.l10n.appsSignatureUnknownKey
          : context.l10n.appsSignatureRejected,
      type: QNotificationType.error,
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _launchApp(BuildContext context) =>
      launchApp(context, () => engine.launch(app, category: category));

  Future<void> _confirmDelete(BuildContext context) =>
      confirmDeleteApp(context, engine: engine, app: app, category: category);
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

/// A square beside the install button, as tall as it: the icon alone, its
/// name in the tooltip for whoever cannot see it.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(10);
    return Tooltip(
      message: context.l10n.appActionDownload,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.divider, width: 1.25),
          borderRadius: radius,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.download, color: colors.textPrimary, size: 22),
          ),
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

  static _ProgressState resolve(
    AppActionType type,
    AppActionStage stage,
    bool cancelling,
  ) {
    final color = switch (type) {
      AppActionType.update => FlipperOriginalColors.green,
      AppActionType.delete => FlipperOriginalColors.danger,
      AppActionType.install => FlipperOriginalColors.accent,
    };
    if (cancelling) {
      return _ProgressState(label: l10n.appActionCancel, color: color);
    }
    if (stage == AppActionStage.queued) {
      return _ProgressState(label: l10n.appActionQueued, color: color);
    }
    if (stage == AppActionStage.check) {
      return _ProgressState(label: l10n.appActionCheck, color: color);
    }
    if (stage == AppActionStage.build) {
      return _ProgressState(label: l10n.appActionBuild, color: color);
    }
    if (type == AppActionType.delete) {
      return _ProgressState(label: l10n.appActionDelete, color: color);
    }
    return _ProgressState(
      label: stage == AppActionStage.upload
          ? l10n.appActionUpload
          : l10n.appActionDownload,
      color: color,
    );
  }
}
