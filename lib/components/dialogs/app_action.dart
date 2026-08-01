import 'package:flutter/material.dart';

import '../../pages/apps/data/models/card.dart';
import '../../pages/apps/data/models/installed_app.dart';
import '../../pages/apps/icons/app_icon.dart';
import '../../pages/apps/manager/widgets/fap_facts.dart';
import '../../theme/theme.dart';

class AppActionSheet {
  static Future<void> show(
    BuildContext context, {
    required InstalledApp app,
    AppCard? initialCard,
    required Future<AppCard> Function() fetchCard,
    required String? Function(String categoryId) categoryNameFor,
    required bool isUpdatable,
    required VoidCallback onUpdate,
    required VoidCallback onOpen,
    required VoidCallback onRestore,
    required VoidCallback onDeleteCopy,
    required VoidCallback onUninstall,
    String? deviceApi,
    String? deviceTarget,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ActionDialog(
        app: app,
        initialCard: initialCard,
        fetchCard: fetchCard,
        categoryNameFor: categoryNameFor,
        isUpdatable: isUpdatable,
        onUpdate: onUpdate,
        onOpen: onOpen,
        onRestore: onRestore,
        onDeleteCopy: onDeleteCopy,
        onUninstall: onUninstall,
        deviceApi: deviceApi,
        deviceTarget: deviceTarget,
      ),
    );
  }
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.app,
    required this.initialCard,
    required this.fetchCard,
    required this.categoryNameFor,
    required this.isUpdatable,
    required this.onUpdate,
    required this.onOpen,
    required this.onRestore,
    required this.onDeleteCopy,
    required this.onUninstall,
    required this.deviceApi,
    required this.deviceTarget,
  });

  final InstalledApp app;
  final AppCard? initialCard;
  final Future<AppCard> Function() fetchCard;
  final String? Function(String categoryId) categoryNameFor;
  final bool isUpdatable;
  final VoidCallback onUpdate;
  final VoidCallback onOpen;
  final VoidCallback onRestore;
  final VoidCallback onDeleteCopy;
  final VoidCallback onUninstall;
  final String? deviceApi;
  final String? deviceTarget;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  AppCard? _card;

  @override
  void initState() {
    super.initState();
    _card = widget.initialCard;
    if (_card == null) _load();
  }

  Future<void> _load() async {
    try {
      final fetched = await widget.fetchCard();
      if (mounted) setState(() => _card = fetched);
    } catch (_) {
      // App not in the catalog (sideloaded) — keep whatever we have.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final app = widget.app;
    final accent = colors.accent;
    final author = _card?.author ?? '';

    final media = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: colors.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: media.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AppIcon(
                      alias: app.alias,
                      size: 26,
                      color: accent,
                      manifest: app.manifest,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.dialogText,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          app.path.isNotEmpty
                              ? app.path
                              : '/ext/apps/${app.folder}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isUpdatable) _UpdateTag(color: colors.success),
                ],
              ),
              const SizedBox(height: 14),
              FapFactsPanel(
                info: app.fap,
                checked: app.fapChecked,
                author: author,
                deviceApi: widget.deviceApi,
                deviceTarget: widget.deviceTarget,
              ),
              const SizedBox(height: 16),
              if (widget.isUpdatable) ...[
                _ActionButton(
                  label: 'Update',
                  icon: Icons.system_update_alt,
                  color: colors.success,
                  filled: true,
                  onTap: () => _run(widget.onUpdate),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Open',
                      icon: Icons.play_arrow_rounded,
                      color: accent,
                      filled: !widget.isUpdatable,
                      onTap: () => _run(widget.onOpen),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Restore',
                      icon: Icons.restore,
                      color: accent,
                      onTap: () => _run(widget.onRestore),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Delete copy',
                      icon: Icons.sd_card_outlined,
                      color: colors.danger,
                      onTap: () => _run(widget.onDeleteCopy),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Uninstall',
                      icon: Icons.delete_outline,
                      color: colors.danger,
                      filled: true,
                      onTap: () => _run(widget.onUninstall),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _run(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }
}

class _UpdateTag extends StatelessWidget {
  const _UpdateTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'UPDATE',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: child,
            ),
    );
  }
}
