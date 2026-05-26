import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../theme.dart';
import '../../../archive/share_remote_file.dart';
import '../controller.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

class FileRow extends StatefulWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.onTap,
    // Dirs
    this.onDelete,
    // Files
    this.onShare,
    this.onCopy,
    this.onCut,
    this.onDownload,
    // Both — returns Future so row can block taps during network op.
    this.onRename,
  });

  final RemoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDownload;
  final Future<void> Function(String)? onRename;

  @override
  State<FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<FileRow> {
  bool _editing = false;
  bool _renaming = false;
  bool _hovered = false;
  late final TextEditingController _renameCtrl;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.entry.name);
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    super.dispose();
  }

  void _startEdit() {
    _renameCtrl.text = widget.entry.name;
    setState(() => _editing = true);
  }

  Future<void> _commitEdit() async {
    final newName = _renameCtrl.text.trim();
    if (newName.isEmpty || newName == widget.entry.name) {
      setState(() => _editing = false);
      return;
    }
    setState(() {
      _editing = false;
      _renaming = true;
    });
    await widget.onRename?.call(newName);
    if (mounted) setState(() => _renaming = false);
  }

  void _showActionsPopup() {
    _FileActionsSheet.show(
      context,
      entry: widget.entry,
      onRename: widget.onRename != null ? _startEdit : null,
      onShare: widget.onShare,
      onCopy: widget.onCopy,
      onCut: widget.onCut,
      onDownload: widget.onDownload,
      onDelete: widget.onDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDir = widget.entry.isDir;
    final asset = isDir
        ? 'assets/flipper_svg/archive/ic_folder.svg'
        : 'assets/flipper_svg/archive/ic_file.svg';
    final tint = isDir ? colors.accent : colors.textSecondary;
    final muted = widget.entry.isHidden;
    final blocked = _editing || _renaming;

    return MouseRegion(
      onEnter: _isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: _isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: blocked ? null : widget.onTap,
          onSecondaryTap: blocked ? null : _showActionsPopup,
          onLongPress: blocked ? null : _showActionsPopup,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                SvgPicture.asset(
                  asset,
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    muted ? colors.textMuted : tint,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editing
                      ? TextField(
                          controller: _renameCtrl,
                          autofocus: true,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _commitEdit(),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _renaming ? _renameCtrl.text : widget.entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: (muted || _renaming)
                                    ? colors.textMuted
                                    : colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!isDir)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  _formatSize(widget.entry.size),
                                  style: TextStyle(
                                      color: colors.textMuted, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(width: 4),
                _buildTrailing(colors, isDir, blocked),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(QAppColors colors, bool isDir, bool blocked) {
    if (_renaming) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
      );
    }
    if (_editing) {
      return _iconBtn(Icons.check, colors.accent, _commitEdit);
    }
    if (!_isDesktop || !_hovered) {
      return const SizedBox.shrink();
    }
    if (isDir) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconBtn(Icons.drive_file_rename_outline, colors.accent, _startEdit),
          const SizedBox(width: 4),
          _iconBtn(Icons.delete_outline, colors.danger, widget.onDelete),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconBtn(Icons.drive_file_rename_outline, colors.accent, _startEdit),
        const SizedBox(width: 4),
        _iconBtn(
          isShareSupported ? Icons.ios_share : Icons.content_copy,
          colors.accent,
          widget.onShare,
        ),
        const SizedBox(width: 4),
        _iconBtn(Icons.more_horiz, colors.accent, _showActionsPopup),
      ],
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ─── Actions popup dialog ─────────────────────────────────────────────────────

class _FileActionsSheet extends StatelessWidget {
  const _FileActionsSheet({
    required this.entry,
    this.onRename,
    this.onShare,
    this.onCopy,
    this.onCut,
    this.onDownload,
    this.onDelete,
  });

  final RemoteEntry entry;
  final VoidCallback? onRename;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  static Future<void> show(
    BuildContext context, {
    required RemoteEntry entry,
    VoidCallback? onRename,
    VoidCallback? onShare,
    VoidCallback? onCopy,
    VoidCallback? onCut,
    VoidCallback? onDownload,
    VoidCallback? onDelete,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _FileActionsSheet(
              entry: entry,
              onRename: onRename,
              onShare: onShare,
              onCopy: onCopy,
              onCut: onCut,
              onDownload: onDownload,
              onDelete: onDelete,
            ),
          ),
        ),
      ),
    );
  }

  List<_Action> _buildActions() {
    final actions = <_Action>[];
    if (onRename != null) {
      actions.add(_Action(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
        onTap: onRename!,
      ));
    }
    if (!entry.isDir) {
      if (onCopy != null) {
        actions.add(_Action(
          icon: Icons.copy_outlined,
          label: 'Copy',
          onTap: onCopy!,
        ));
      }
      if (onCut != null) {
        actions.add(_Action(
          icon: Icons.content_cut,
          label: 'Cut',
          onTap: onCut!,
        ));
      }
      if (onDownload != null) {
        actions.add(_Action(
          icon: Icons.download_outlined,
          label: 'Download',
          onTap: onDownload!,
        ));
      }
      if (onShare != null) {
        actions.add(_Action(
          icon: isShareSupported ? Icons.ios_share : Icons.content_copy,
          label: isShareSupported ? 'Share' : 'Copy',
          onTap: onShare!,
        ));
      }
    }
    if (onDelete != null) {
      actions.add(_Action(
        icon: Icons.delete_outline,
        label: 'Delete',
        onTap: onDelete!,
        destructive: true,
      ));
    }
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDir = entry.isDir;
    final asset = isDir
        ? 'assets/flipper_svg/archive/ic_folder.svg'
        : 'assets/flipper_svg/archive/ic_file.svg';
    final tint = isDir ? colors.accent : colors.textSecondary;
    final actions = _buildActions();

    return Material(
      color: colors.card,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SvgPicture.asset(
                      asset,
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (!isDir)
                          Text(
                            _formatSize(entry.size),
                            style:
                                TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in actions)
                    SizedBox(width: 72, height: 72, child: _ActionTile(action: a)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDestructive = action.destructive;
    final iconColor = isDestructive ? colors.danger : colors.textSecondary;
    final labelColor = isDestructive ? colors.danger : colors.textSecondary;

    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          action.onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: iconColor, size: 22),
            const SizedBox(height: 5),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action {
  _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}
