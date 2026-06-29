import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import '../../../widgets/progress_button.dart';
import 'controller.dart';
import 'local_repo.dart';
import 'settings.dart';

class IrLibSettingsDialog extends StatefulWidget {
  const IrLibSettingsDialog({super.key, required this.controller});

  final IrLibController controller;

  static Future<void> show(BuildContext context, IrLibController controller) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IrLibSettingsDialog(controller: controller),
    );
  }

  @override
  State<IrLibSettingsDialog> createState() => _IrLibSettingsDialogState();
}

class _IrLibSettingsDialogState extends State<IrLibSettingsDialog> {
  late TextEditingController _tokenCtrl;
  late TextEditingController _urlCtrl;
  String? _urlError;
  bool _showToken = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _tokenCtrl = TextEditingController(text: s.githubToken);
    _urlCtrl = TextEditingController(
      text: IrdbRepoRef(owner: s.owner, repo: s.repo, branch: s.branch).toUrl(),
    );
    widget.controller.addListener(_onCtrl);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _tokenCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  IrdbRepoRef? _parsedRef() {
    final urlText =
        _urlCtrl.text.trim().isEmpty ? kDefaultIrdbUrl : _urlCtrl.text.trim();
    return IrdbRepoRef.tryParse(urlText);
  }

  Future<bool> _persistFields() async {
    final ref = _parsedRef();
    if (ref == null) {
      setState(() => _urlError = 'Enter a valid GitHub URL');
      return false;
    }
    setState(() => _urlError = null);
    final cur = widget.controller.settings;
    if (cur.owner == ref.owner &&
        cur.repo == ref.repo &&
        cur.branch == ref.branch &&
        cur.githubToken == _tokenCtrl.text.trim()) {
      return true;
    }
    await widget.controller.updateSettings(cur.copyWith(
      owner: ref.owner,
      repo: ref.repo,
      branch: ref.branch,
      githubToken: _tokenCtrl.text.trim(),
    ));
    return true;
  }

  Future<void> _onPrimaryAction() async {
    if (widget.controller.downloading) return;
    if (widget.controller.localAvailable) {
      final ok = await widget.controller.deleteLocalRepo();
      if (!mounted) return;
      if (ok) {
        context.showNotification(
          'Local IRDB deleted',
          type: QNotificationType.good,
        );
      } else {
        context.showNotification(
          widget.controller.error ?? 'Failed to delete',
          type: QNotificationType.error,
        );
      }
      return;
    }
    if (!await _persistFields()) return;
    final ok = await widget.controller.downloadLocalRepo();
    if (!mounted) return;
    if (ok) {
      context.showNotification(
        'IRDB downloaded',
        type: QNotificationType.good,
      );
    } else {
      context.showNotification(
        widget.controller.error ?? 'Download failed',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _save() async {
    if (widget.controller.downloading) return;
    setState(() => _saving = true);
    final ok = await _persistFields();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final downloading = widget.controller.downloading;
    final localAvailable = widget.controller.localAvailable;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text('IRDB', style: TextStyle(color: colors.textPrimary)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: _urlCtrl,
                label: 'Repository URL',
                colors: colors,
                errorText: _urlError,
                enabled: !downloading,
              ),
              const SizedBox(height: 8),
              _field(
                controller: _tokenCtrl,
                label: 'GitHub token (optional)',
                colors: colors,
                obscure: !_showToken,
                enabled: !downloading,
                suffix: IconButton(
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                    color: colors.textMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
              const SizedBox(height: 14),
              _PrimaryActionButton(
                colors: colors,
                downloading: downloading,
                localAvailable: localAvailable,
                progress: widget.controller.downloadProgress,
                onPressed: _onPrimaryAction,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              (_saving || downloading) ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: colors.accent),
          onPressed: (_saving || downloading) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required QAppColors colors,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
    String? hint,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textMuted, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.6), fontSize: 13),
        errorText: errorText,
        isDense: true,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.textMuted.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.textMuted.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.colors,
    required this.downloading,
    required this.localAvailable,
    required this.progress,
    required this.onPressed,
  });

  final QAppColors colors;
  final bool downloading;
  final bool localAvailable;
  final IrLibDownloadProgress? progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color = colors.accent;
    double? value;
    bool indeterminate = false;
    bool showPercent = false;
    VoidCallback? action;

    if (downloading) {
      final p = progress;
      final unpacking = p?.stage == 'Unpacking' || (p?.isExtracting ?? false);
      final hasPercent = p != null &&
          ((unpacking && p.totalFiles > 0) ||
              (!unpacking && (p.total > 0 || p.received > 0)));
      label = unpacking ? 'UNPACKING' : 'DOWNLOADING';
      if (hasPercent) {
        value = p.fraction;
        showPercent = true;
      } else {
        indeterminate = true;
      }
    } else if (localAvailable) {
      label = 'DELETE';
      action = onPressed;
    } else {
      label = 'DOWNLOAD';
      action = onPressed;
    }

    return ProgressButton(
      text: label,
      color: color,
      progress: value,
      indeterminate: indeterminate,
      showPercent: showPercent,
      onPressed: action,
      textStyle: ProgressButton.defaultTextStyle.copyWith(fontSize: 38),
    );
  }
}
