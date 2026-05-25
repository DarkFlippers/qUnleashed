import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../theme.dart';
import '../../../archive/share_remote_file.dart';
import '../controller.dart';

enum _FileAction { copy, cut, download, delete }

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

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: blocked ? null : widget.onTap,
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
              if (_renaming)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                )
              else if (_editing)
                _iconBtn(Icons.check, colors.accent, _commitEdit)
              else if (isDir)
                _DirActions(colors: colors, onRename: _startEdit, onDelete: widget.onDelete)
              else
                _FileActions(
                  colors: colors,
                  onRename: _startEdit,
                  onShare: widget.onShare,
                  onCopy: widget.onCopy,
                  onCut: widget.onCut,
                  onDownload: widget.onDownload,
                  onDelete: widget.onDelete,
                ),
            ],
          ),
        ),
      ),
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

class _DirActions extends StatelessWidget {
  const _DirActions({
    required this.colors,
    required this.onRename,
    required this.onDelete,
  });

  final QAppColors colors;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.drive_file_rename_outline, colors.accent, onRename),
        const SizedBox(width: 8),
        _btn(Icons.delete_outline, colors.accent, onDelete),
      ],
    );
  }

  Widget _btn(IconData icon, Color color, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }
}

class _FileActions extends StatelessWidget {
  const _FileActions({
    required this.colors,
    required this.onRename,
    this.onShare,
    this.onCopy,
    this.onCut,
    this.onDownload,
    this.onDelete,
  });

  final QAppColors colors;
  final VoidCallback onRename;
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.drive_file_rename_outline, colors.accent, onRename),
        const SizedBox(width: 8),
        _btn(
          isShareSupported ? Icons.ios_share : Icons.content_copy,
          colors.accent,
          onShare,
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            color: colors.accent,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showMenu(ctx),
          ),
        ),
      ],
    );
  }

  Future<void> _showMenu(BuildContext ctx) async {
    final box = ctx.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(ctx).overlay!.context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    );
    final action = await showMenu<_FileAction>(
      context: ctx,
      position: pos,
      color: colors.card,
      items: [
        PopupMenuItem(
          value: _FileAction.copy,
          child: Text('Copy', style: TextStyle(color: colors.textPrimary)),
        ),
        PopupMenuItem(
          value: _FileAction.cut,
          child: Text('Cut', style: TextStyle(color: colors.textPrimary)),
        ),
        PopupMenuItem(
          value: _FileAction.download,
          child: Text('Download', style: TextStyle(color: colors.textPrimary)),
        ),
        PopupMenuItem(
          value: _FileAction.delete,
          child: Text('Delete', style: TextStyle(color: colors.danger)),
        ),
      ],
    );
    switch (action) {
      case _FileAction.copy:
        onCopy?.call();
      case _FileAction.cut:
        onCut?.call();
      case _FileAction.download:
        onDownload?.call();
      case _FileAction.delete:
        onDelete?.call();
      case null:
        break;
    }
  }

  Widget _btn(IconData icon, Color color, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }
}
