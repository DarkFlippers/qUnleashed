import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../../../components/filelist/progress_fill.dart';
import '../columns.dart';
import '../controller.dart';
import 'file_row.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

class FileColumnHeader extends StatelessWidget {
  const FileColumnHeader({
    super.key,
    required this.cols,
    required this.sortKey,
    required this.sortAsc,
    required this.onSort,
    this.selectionMode = false,
  });

  final List<SizedFileCol> cols;
  final String sortKey;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: kFileHeaderHeight,
      color: fileBarColor(colors),
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (selectionMode) const SizedBox(width: kFileSelectionWidth),
          for (final e in cols)
            _HeaderCell(
              col: e.col,
              width: e.width,
              active: sortKey == e.col.sortKey,
              asc: sortAsc,
              onSort: e.col.sortKey != null
                  ? () => onSort(e.col.sortKey!)
                  : null,
            ),
          const SizedBox(width: kFileTrailingWidth),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.col,
    required this.width,
    required this.active,
    required this.asc,
    required this.onSort,
  });

  final FileCol col;
  final double width;
  final bool active;
  final bool asc;
  final VoidCallback? onSort;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Widget cell = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          col.label.toUpperCase(),
          style: TextStyle(
            color: active ? colors.textSecondary : colors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 2),
          Icon(
            asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 10,
            color: colors.textSecondary,
          ),
        ],
      ],
    );
    if (onSort != null) {
      cell = GestureDetector(onTap: onSort, child: cell);
    }
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: col.right ? Alignment.centerRight : Alignment.centerLeft,
          child: cell,
        ),
      ),
    );
  }
}

class FileTableRow extends StatefulWidget {
  const FileTableRow({
    super.key,
    required this.entry,
    required this.cols,
    required this.actions,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.autoEdit = false,
    this.progress,
  });

  final RemoteEntry entry;
  final List<SizedFileCol> cols;
  final FileEntryActions actions;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final bool autoEdit;
  final double? progress;

  @override
  State<FileTableRow> createState() => _FileTableRowState();
}

class _FileTableRowState extends State<FileTableRow> {
  bool _editing = false;
  bool _renaming = false;
  bool _hovered = false;
  late final TextEditingController _renameCtrl;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.entry.name);
    if (widget.autoEdit) _beginAutoEdit();
  }

  @override
  void didUpdateWidget(FileTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoEdit && !oldWidget.autoEdit && !_editing && !_renaming) {
      _renameCtrl.text = widget.entry.name;
      setState(_beginAutoEdit);
    }
  }

  void _beginAutoEdit() {
    _editing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _renameCtrl.text;
      final dot = text.lastIndexOf('.');
      final end = dot > 0 ? dot : text.length;
      _renameCtrl.selection = TextSelection(baseOffset: 0, extentOffset: end);
    });
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
    final blocked = _editing || _renaming;

    return MouseRegion(
      onEnter: _isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: _isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: Material(
        color: widget.selected
            ? colors.accent.withValues(alpha: 0.12)
            : colors.card,
        child: Stack(
          children: [
            ProgressFill(progress: widget.progress),
            InkWell(
              onTap: blocked ? null : widget.onTap,
              onLongPress: blocked ? null : widget.onLongPress,
              onSecondaryTap: blocked ? null : _showActionsSheet,
              child: Container(
                height: kFileRowHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.divider.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    if (widget.selectionMode) _selectionIndicator(colors),
                    for (final e in widget.cols)
                      SizedBox(
                        width: e.width,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _cell(colors, e.col),
                        ),
                      ),
                    _trailing(colors),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionIndicator(QAppColors colors) {
    return SizedBox(
      width: kFileSelectionWidth,
      child: Icon(
        widget.selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 18,
        color: widget.selected ? colors.accent : colors.textMuted,
      ),
    );
  }

  Widget _cell(QAppColors colors, FileCol col) {
    if (col.width == 0) return _nameCell(colors);
    final muted = widget.entry.isHidden;
    return Align(
      alignment: col.right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        fileColumnValue(col, widget.entry),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? colors.textMuted : colors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _nameCell(QAppColors colors) {
    final muted = widget.entry.isHidden;
    return Row(
      children: [
        FileIconBadge(entry: widget.entry, size: 28, muted: muted),
        const SizedBox(width: 8),
        Expanded(
          child: _editing
              ? TextField(
                  controller: _renameCtrl,
                  autofocus: true,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _commitEdit(),
                )
              : Text(
                  _renaming ? _renameCtrl.text : widget.entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (muted || _renaming)
                        ? colors.textMuted
                        : colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _trailing(QAppColors colors) {
    if (_renaming) {
      return SizedBox(
        width: kFileTrailingWidth,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
        ),
      );
    }
    if (_editing) {
      return SizedBox(
        width: kFileTrailingWidth,
        child: _iconBtn(Icons.check, colors.accent, _commitEdit),
      );
    }
    if (widget.selectionMode) {
      return const SizedBox(width: kFileTrailingWidth);
    }
    if (_isDesktop && _hovered) {
      return SizedBox(
        width: kFileTrailingWidth,
        child: _iconBtn(Icons.more_horiz, colors.accent, _showActionsSheet),
      );
    }
    if (widget.entry.isDir) {
      return SizedBox(
        width: kFileTrailingWidth,
        child: Icon(Icons.chevron_right, size: 17, color: colors.textMuted),
      );
    }
    return SizedBox(
      width: kFileTrailingWidth,
      child: _iconBtn(Icons.more_horiz, colors.textMuted, _showActionsSheet),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 17),
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: kFileTrailingWidth,
        minHeight: kFileRowHeight,
      ),
      onPressed: onPressed,
    );
  }
}
