import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../data/models/card.dart';
import '../data/models/installed_app.dart';
import '../icons/app_icon.dart';

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

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  AppCard? _card;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _card = widget.initialCard;
    final shots = _card?.currentVersion?.screenshots ?? const [];
    if (_card == null || shots.isEmpty) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fetched = await widget.fetchCard();
      if (mounted) setState(() => _card = fetched);
    } catch (_) {
      // App not in the catalog (sideloaded) — keep whatever we have.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final app = widget.app;
    final accent = colors.accent;
    final card = _card;
    final cv = card?.currentVersion;
    final shots = cv?.screenshots ?? const <String>[];
    final author = card?.author ?? '';
    final version = cv?.version ?? '';
    final category =
        card != null ? (widget.categoryNameFor(card.categoryId) ?? '') : '';

    final meta = <String>[
      if (category.isNotEmpty) category,
      if (version.isNotEmpty) 'v$version',
      if (app.size > 0) _fmtSize(app.size),
    ].join('  ·  ');

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
                        if (author.isNotEmpty)
                          Text(
                            'by $author',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (widget.isUpdatable) _UpdateTag(color: colors.success),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                '/ext/apps/${app.folder}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              _screenshots(colors, shots),
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

  Widget _screenshots(QAppColors colors, List<String> shots) {
    if (shots.isEmpty) {
      return Container(
        height: 118,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: _loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.accent),
              )
            : Text(
                'No screenshots',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
      );
    }
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _Shot(url: shots[i], colors: colors),
      ),
    );
  }

  void _run(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  String _fmtSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var b = bytes.toDouble();
    var i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
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

class _Shot extends StatelessWidget {
  const _Shot({required this.url, required this.colors});

  final String url;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 256 / 128,
      child: Container(
        decoration: BoxDecoration(
          color: colors.isDark ? colors.screenBackground : colors.accent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 2),
        ),
        padding: const EdgeInsets.all(4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
            loadingBuilder: (ctx, child, progress) => progress == null
                ? child
                : Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    ),
                  ),
          ),
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
