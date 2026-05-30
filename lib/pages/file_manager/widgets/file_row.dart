import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../share_remote_file.dart';
import '../controller.dart';
import 'file_type.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Shared callbacks for a directory entry, threaded into both the list row and
/// the grid tile so the action set stays identical across view modes.
class FileEntryActions {
  const FileEntryActions({
    this.onDelete,
    this.onShare,
    this.onCopy,
    this.onCut,
    this.onDownload,
    this.onRename,
  });

  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDownload;

  /// Returns a Future so the caller can block taps during the network op.
  final Future<void> Function(String)? onRename;
}

// ─── Icon badge ───────────────────────────────────────────────────────────────

class FileIconBadge extends StatelessWidget {
  const FileIconBadge({
    super.key,
    required this.entry,
    this.size = 40,
    this.muted = false,
  });

  final RemoteEntry entry;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visual = fileVisualFor(entry, colors);
    final color = muted ? colors.textMuted : visual.color;
    final glyph = size * 0.55;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: visual.asset != null
          ? SvgPicture.asset(
              visual.asset!,
              width: glyph,
              height: glyph,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          : Icon(visual.icon, size: glyph, color: color),
    );
  }
}

class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected, this.size = 22});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.accent : Colors.transparent,
        border: Border.all(
          color: selected ? colors.accent : colors.textMuted,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.6, color: colors.onAccent)
          : null,
    );
  }
}

// ─── List row ───────────────────────────────────────────────────────────────

class FileRow extends StatefulWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.onTap,
    required this.actions,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final RemoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FileEntryActions actions;
  final bool selectionMode;
  final bool selected;

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
    await widget.actions.onRename?.call(newName);
    if (mounted) setState(() => _renaming = false);
  }

  void _showActionsSheet() {
    FileActionsSheet.show(
      context,
      entry: widget.entry,
      actions: widget.actions,
      onRenameInline: widget.actions.onRename != null ? _startEdit : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDir = widget.entry.isDir;
    final muted = widget.entry.isHidden;
    final blocked = _editing || _renaming;

    return MouseRegion(
      onEnter: _isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: _isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: Material(
        color: widget.selected ? colors.accent.withValues(alpha: 0.12) : colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: blocked ? null : widget.onTap,
          onLongPress: blocked ? null : (widget.onLongPress ?? _showActionsSheet),
          onSecondaryTap: blocked ? null : _showActionsSheet,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    FileIconBadge(entry: widget.entry, muted: muted),
                    if (widget.selectionMode)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.card,
                          ),
                          padding: const EdgeInsets.all(1),
                          child: _SelectionCheck(
                            selected: widget.selected,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editing
                      ? TextField(
                          controller: _renameCtrl,
                          autofocus: true,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _subtitle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 12,
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

  String _subtitle() {
    final e = widget.entry;
    if (e.isDir) return fileTypeLabel(e);
    return '${fileTypeLabel(e)} · ${formatBytes(e.size)}';
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
    if (widget.selectionMode) {
      return const SizedBox(width: 8);
    }
    // Desktop hover reveals quick actions; mobile relies on long-press sheet.
    if (_isDesktop && _hovered) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconBtn(Icons.drive_file_rename_outline, colors.accent, _startEdit),
          if (!isDir) ...[
            const SizedBox(width: 2),
            _iconBtn(
              isShareSupported ? Icons.ios_share : Icons.content_copy,
              colors.accent,
              widget.actions.onShare,
            ),
          ],
          const SizedBox(width: 2),
          _iconBtn(Icons.more_vert, colors.textSecondary, _showActionsSheet),
        ],
      );
    }
    if (isDir) {
      return Icon(Icons.chevron_right, size: 22, color: colors.textMuted);
    }
    return _iconBtn(Icons.more_vert, colors.textMuted, _showActionsSheet);
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
    );
  }
}

// ─── Grid tile ───────────────────────────────────────────────────────────────

class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.actions,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final RemoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FileEntryActions actions;
  final bool selectionMode;
  final bool selected;

  void _showActionsSheet(BuildContext context) {
    FileActionsSheet.show(context, entry: entry, actions: actions);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = entry.isHidden;

    return Material(
      color: selected ? colors.accent.withValues(alpha: 0.12) : colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress ?? () => _showActionsSheet(context),
        onSecondaryTap: () => _showActionsSheet(context),
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              // A fixed-height name block keeps every icon on the same baseline
              // so the row reads as an evenly aligned, centered grid.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FileIconBadge(entry: entry, size: 44, muted: muted),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: Text(
                      entry.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted ? colors.textMuted : colors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.isDir ? 'Folder' : formatBytes(entry.size),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: _SelectionCheck(selected: selected, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Actions bottom sheet ─────────────────────────────────────────────────────

class FileActionsSheet extends StatelessWidget {
  const FileActionsSheet._({
    required this.entry,
    required this.actions,
    this.onRenameInline,
  });

  final RemoteEntry entry;
  final FileEntryActions actions;
  final VoidCallback? onRenameInline;

  static Future<void> show(
    BuildContext context, {
    required RemoteEntry entry,
    required FileEntryActions actions,
    VoidCallback? onRenameInline,
  }) {
    final colors = context.appColors;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FileActionsSheet._(
        entry: entry,
        actions: actions,
        onRenameInline: onRenameInline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDir = entry.isDir;
    final rows = <Widget>[];

    void add(IconData icon, String label, VoidCallback? onTap,
        {bool destructive = false}) {
      if (onTap == null) return;
      rows.add(_ActionRow(
        icon: icon,
        label: label,
        destructive: destructive,
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ));
    }

    final renameTap = onRenameInline ??
        (actions.onRename != null
            ? () => actions.onRename!.call(entry.name)
            : null);
    add(Icons.drive_file_rename_outline, 'Rename', renameTap);
    if (!isDir) {
      add(Icons.copy_outlined, 'Copy', actions.onCopy);
      add(Icons.content_cut, 'Cut', actions.onCut);
      add(Icons.download_outlined, 'Download', actions.onDownload);
      add(
        isShareSupported ? Icons.ios_share : Icons.content_copy,
        isShareSupported ? 'Share' : 'Copy to clipboard',
        actions.onShare,
      );
    }
    add(Icons.delete_outline, 'Delete', actions.onDelete, destructive: true);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              children: [
                FileIconBadge(entry: entry, size: 44),
                const SizedBox(width: 14),
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
                      const SizedBox(height: 2),
                      Text(
                        isDir
                            ? 'Folder'
                            : '${fileTypeLabel(entry)} · ${formatBytes(entry.size)}',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.divider),
          ...rows,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = destructive ? colors.danger : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 18),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
