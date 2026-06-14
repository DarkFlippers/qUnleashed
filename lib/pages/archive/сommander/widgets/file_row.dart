import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../components/icon.dart';
import '../../../../services/repository/app.dart' as icon_repo;
import '../../../../theme/theme.dart';
import '../../overview/fap_icon.dart';
import '../../overview/widgets/actions_sheet.dart';
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
    this.onEmulate,
    this.onEdit,
  });

  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDownload;

  /// Category capabilities surfaced for files that map to an archive category,
  /// so the file manager offers the same actions as the category pages.
  final VoidCallback? onEmulate;
  final VoidCallback? onEdit;

  /// Returns a Future so the caller can block taps during the network op.
  final Future<void> Function(String)? onRename;
}

// ─── Icon badge ───────────────────────────────────────────────────────────────

class FileIconBadge extends StatefulWidget {
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
  State<FileIconBadge> createState() => _FileIconBadgeState();
}

class _FileIconBadgeState extends State<FileIconBadge> {
  String? _fapAppId;
  Uint8List? _fapIcon;

  @override
  void initState() {
    super.initState();
    _resolveFapIcon();
  }

  @override
  void didUpdateWidget(FileIconBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.name != widget.entry.name) {
      _fapIcon = null;
      _resolveFapIcon();
    }
  }

  void _resolveFapIcon() {
    final name = widget.entry.name;
    if (widget.entry.isDir || !name.toLowerCase().endsWith('.fap')) {
      _fapAppId = null;
      return;
    }
    final appId = name.substring(0, name.length - 4);
    _fapAppId = appId;
    icon_repo.readFapIcon(appId).then((bytes) {
      if (mounted && _fapAppId == appId && bytes != null) {
        setState(() => _fapIcon = bytes);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visual = fileVisualFor(widget.entry, colors);
    final color = widget.muted ? colors.textMuted : visual.color;
    final glyph = widget.size * 0.55;
    final fapIcon = _fapIcon;

    final Widget child;
    if (fapIcon != null) {
      child = QIcon.xbm(
        bytes: fapIcon,
        width: fapIconWidth,
        height: fapIconHeight,
        cacheKey: 'repo:${widget.entry.name}',
        color: color,
        size: glyph,
      );
    } else if (visual.asset != null) {
      child = SvgPicture.asset(
        visual.asset!,
        width: glyph,
        height: glyph,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    } else {
      child = Icon(visual.icon, size: glyph, color: color);
    }

    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(widget.size * 0.28),
      ),
      child: child,
    );
  }
}

/// A small accent check-badge that floats on top of a file icon's corner while
/// the entry is selected. A card-colored ring lifts it off the icon, and the
/// parent stacks use `Clip.none` so it is never clipped by the icon bounds.
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck();

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accent,
        border: Border.all(color: colors.card, width: 2),
      ),
      child: Icon(Icons.check, size: _size * 0.6, color: colors.onAccent),
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
        color: widget.selected
            ? colors.accent.withValues(alpha: 0.12)
            : colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: blocked ? null : widget.onTap,
          onLongPress: blocked
              ? null
              : (widget.onLongPress ?? _showActionsSheet),
          onSecondaryTap: blocked ? null : _showActionsSheet,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FileIconBadge(entry: widget.entry, muted: muted),
                    if (widget.selectionMode && widget.selected)
                      const Positioned(
                        right: -3,
                        bottom: -3,
                        child: _SelectionCheck(),
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
        child: Padding(
          // Fixed top inset + fixed name height → the icon always sits at the
          // same position regardless of how many lines the name takes.
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  FileIconBadge(entry: entry, size: 44, muted: muted),
                  if (selectionMode && selected)
                    const Positioned(
                      right: -3,
                      bottom: -3,
                      child: _SelectionCheck(),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 30,
                child: Text(
                  entry.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted ? colors.textMuted : colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Actions bottom sheet ─────────────────────────────────────────────────────

/// Builds the file-manager action set for a [RemoteEntry] and presents it via
/// the shared [ActionsSheet], so it stays visually and behaviourally identical
/// to the archive category pages.
class FileActionsSheet {
  const FileActionsSheet._();

  static Future<void> show(
    BuildContext context, {
    required RemoteEntry entry,
    required FileEntryActions actions,
    VoidCallback? onRenameInline,
  }) {
    final isDir = entry.isDir;
    final items = <ActionItem>[];

    void add(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool destructive = false,
    }) {
      if (onTap == null) return;
      items.add(
        ActionItem(
          icon: icon,
          label: label,
          destructive: destructive,
          onTap: onTap,
        ),
      );
    }

    final renameTap =
        onRenameInline ??
        (actions.onRename != null
            ? () => actions.onRename!.call(entry.name)
            : null);
    add(Icons.drive_file_rename_outline, 'Rename', renameTap);
    add(Icons.copy_outlined, 'Copy', actions.onCopy);
    add(Icons.drive_file_move_outlined, 'Move', actions.onCut);
    add(Icons.download_outlined, 'Download', actions.onDownload);
    add(Icons.play_arrow, 'Emulate', actions.onEmulate);
    add(Icons.edit_note, 'Edit', actions.onEdit);
    if (!isDir) {
      add(
        isShareSupported ? Icons.ios_share : Icons.content_copy,
        isShareSupported ? 'Share' : 'Clipboard',
        actions.onShare,
      );
    }
    add(Icons.delete_outline, 'Delete', actions.onDelete, destructive: true);

    final subtitle = isDir
        ? 'Folder'
        : '${fileTypeLabel(entry)} · ${formatBytes(entry.size)}';

    return ActionsSheet.show(
      context,
      leading: FileIconBadge(entry: entry, size: 40),
      title: entry.name,
      subtitle: subtitle,
      actions: items,
    );
  }
}
