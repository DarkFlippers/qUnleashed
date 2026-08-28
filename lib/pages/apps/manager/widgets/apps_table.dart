import 'package:flutter/material.dart';

import '../../../../components/filelist/columns.dart';
import '../../../../components/filelist/progress_fill.dart';
import '../../../../components/filelist/table.dart';
import '../../../../components/format.dart';
import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';

/// The facts every apps table sorts by, whatever the row stands for.
typedef AppsRowFacts = ({String name, String folder, int size, String version});

/// Sort key and direction of an apps table, plus the comparison itself.
class AppsSortState {
  String key = 'name';
  bool asc = true;

  void select(String next) {
    if (key == next) {
      asc = !asc;
    } else {
      key = next;
      asc = true;
    }
  }

  int compare(AppsRowFacts a, AppsRowFacts b) {
    final int cmp;
    switch (key) {
      case 'folder':
        final f = a.folder.toLowerCase().compareTo(b.folder.toLowerCase());
        cmp = f != 0 ? f : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case 'size':
        cmp = a.size.compareTo(b.size);
      case 'version':
        cmp = a.version.compareTo(b.version);
      default:
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return asc ? cmp : -cmp;
  }
}

List<SizedColumn> appsTableColumns(double avail) {
  const sizeW = 64.0;
  const versionW = 74.0;
  const folderW = 118.0;
  final showFolder = avail > 460;
  final showVersion = avail > 360;
  final fixed =
      sizeW + (showFolder ? folderW : 0) + (showVersion ? versionW : 0);
  final nameW = (avail - fixed - 24)
      .clamp(kNameMinWidth, double.infinity)
      .toDouble();
  return [
    (col: const ArchiveCol('Name / Folder', 0, sortKey: 'name'), width: nameW),
    if (showFolder)
      (
        col: const ArchiveCol('Folder', folderW, sortKey: 'folder'),
        width: folderW,
      ),
    if (showVersion)
      (
        col: const ArchiveCol(
          'Version',
          versionW,
          sortKey: 'version',
          right: true,
        ),
        width: versionW,
      ),
    (
      col: const ArchiveCol('Size', sizeW, sortKey: 'size', right: true),
      width: sizeW,
    ),
  ];
}

/// Sortable header plus the pull-to-refresh list of [items]; [rowBuilder] gets
/// the resolved columns so a page only describes its own cells.
class AppsTable<T> extends StatelessWidget {
  const AppsTable({
    super.key,
    required this.items,
    required this.sort,
    required this.onSort,
    required this.header,
    required this.onRefresh,
    required this.rowBuilder,
  });

  final List<T> items;
  final AppsSortState sort;
  final ValueChanged<String> onSort;
  final Color header;
  final Future<void> Function() onRefresh;
  final Widget Function(T item, List<SizedColumn> cols) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = appsTableColumns(constraints.maxWidth);
        return Column(
          children: [
            ArchiveColumnHeader(
              cols: cols,
              sortKey: sort.key,
              sortAsc: sort.asc,
              onSort: onSort,
              colors: colors,
            ),
            Expanded(
              child: RefreshIndicator(
                color: header,
                displacement: 15,
                onRefresh: onRefresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => rowBuilder(items[i], cols),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AppsTableRow extends StatelessWidget {
  const AppsTableRow({
    super.key,
    required this.cols,
    required this.header,
    required this.progress,
    required this.onTap,
    required this.cell,
  });

  final List<SizedColumn> cols;
  final Color header;
  final double? progress;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, ArchiveCol col) cell;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      child: Stack(
        children: [
          ProgressFill(progress: progress),
          InkWell(
            onTap: onTap,
            splashColor: header.withValues(alpha: 0.06),
            highlightColor: header.withValues(alpha: 0.04),
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
                  for (final e in cols)
                    SizedBox(
                      width: e.width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: cell(context, e.col),
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
}

class AppsIconBadge extends StatelessWidget {
  const AppsIconBadge({
    super.key,
    required this.color,
    required this.size,
    required this.builder,
  });

  final Color color;
  final double size;
  final Widget Function(Color foreground) builder;

  @override
  Widget build(BuildContext context) {
    final style = QIconBadgeStyle.of(context, color, darkOpacity: 0.14);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: builder(style.foreground),
    );
  }
}

class AppsNameCell extends StatelessWidget {
  const AppsNameCell({
    super.key,
    required this.header,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color header;
  final Widget Function(Color foreground) icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        AppsIconBadge(color: header, size: 28, builder: icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AppsFolderCell extends StatelessWidget {
  const AppsFolderCell({super.key, required this.folder});

  final String folder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        folder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
    );
  }
}

class AppsSizeCell extends StatelessWidget {
  const AppsSizeCell({super.key, required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        bytes > 0 ? formatBytesScaled(bytes, maxUnit: 2) : '—',
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    );
  }
}
