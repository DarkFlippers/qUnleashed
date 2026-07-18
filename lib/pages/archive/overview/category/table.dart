import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../../data/category.dart';
import '../../data/models/key.dart';
import '../widgets/progress_fill.dart';
import 'columns.dart';

const double kSelectionIndicatorWidth = 26;

class ArchiveColumnHeader extends StatelessWidget {
  const ArchiveColumnHeader({
    super.key,
    required this.cols,
    required this.sortKey,
    required this.sortAsc,
    required this.onSort,
    required this.colors,
    this.selectionMode = false,
  });

  final List<SizedColumn> cols;
  final String sortKey;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final QAppColors colors;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kHeaderHeight,
      color: colors.card.withValues(alpha: 0.7),
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (selectionMode) const SizedBox(width: kSelectionIndicatorWidth),
          for (final e in cols)
            _HeaderCell(
              col: e.col,
              width: e.width,
              active: sortKey == e.col.sortKey,
              asc: sortAsc,
              onSort: e.col.sortKey != null
                  ? () => onSort(e.col.sortKey!)
                  : null,
              colors: colors,
            ),
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
    required this.colors,
  });

  final ArchiveCol col;
  final double width;
  final bool active;
  final bool asc;
  final VoidCallback? onSort;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: active ? colors.textSecondary : colors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );

    Widget cell = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: col.right
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Text(col.label.toUpperCase(), style: textStyle),
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

class ArchiveTableRow extends StatelessWidget {
  const ArchiveTableRow({
    super.key,
    required this.flipperKey,
    required this.cols,
    required this.colors,
    required this.cat,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.progress,
  });

  final ArchiveKey flipperKey;
  final List<SizedColumn> cols;
  final QAppColors colors;
  final ArchiveCategory cat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final k = flipperKey;
    return Material(
      color: selected ? cat.color.withValues(alpha: 0.12) : colors.card,
      child: Stack(
        children: [
          ProgressFill(progress: progress),
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            splashColor: cat.color.withValues(alpha: 0.06),
            highlightColor: cat.color.withValues(alpha: 0.04),
            child: Container(
              height: kRowHeight,
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
                  if (selectionMode) _selectionIndicator(),
                  for (final e in cols)
                    SizedBox(
                      width: e.width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _cellContent(e.col, k),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionIndicator() {
    return SizedBox(
      width: kSelectionIndicatorWidth,
      child: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: selected ? cat.color : colors.textMuted,
      ),
    );
  }

  Widget _cellContent(ArchiveCol col, ArchiveKey k) {
    if (col.width == 0) return _nameCell(k);
    if (col.sortKey == 'protocol') return _protocolCell(k);
    final text = columnValue(col, k);
    final mono =
        col.sortKey == 'uid' ||
        col.sortKey == 'data' ||
        col.sortKey == 'frequency';
    if (mono) return _monoCell(text, right: col.right);
    final muted = col.sortKey == 'size' || col.sortKey == 'mtime';
    return _textCell(text, right: col.right, muted: muted);
  }

  Widget _protocolCell(ArchiveKey k) {
    final proto = k.protocol;
    if (proto == null) return _textCell('—');
    final hasRaw = k.meta?['has_raw'] == '1';
    return Row(
      children: [
        Flexible(
          child: Text(
            proto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ),
        if (hasRaw && proto != 'RAW') ...[
          const SizedBox(width: 4),
          Text(
            '(raw)',
            style: TextStyle(color: colors.textMuted, fontSize: 10),
          ),
        ],
      ],
    );
  }

  Widget _nameCell(ArchiveKey k) {
    final relDir = k.subFolder.isEmpty ? '/' : '/${k.subFolder}/';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          k.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          relDir,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }

  Widget _textCell(String text, {bool right = false, bool muted = false}) {
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? colors.textMuted : colors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _monoCell(String text, {bool right = false}) {
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          fontFamily: 'monospace',
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
