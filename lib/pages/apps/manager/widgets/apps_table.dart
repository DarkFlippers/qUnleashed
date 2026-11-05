import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../components/filelist/columns.dart';
import '../../../../components/filelist/folder_sort.dart';
import '../../../../components/filelist/progress_fill.dart';
import '../../../../components/filelist/table.dart';
import '../../../../components/filelist/toolbar.dart';
import '../../../../components/format.dart';
import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';

/// The facts every apps-manager table sorts by, whatever the row stands for.
typedef AppsRowFacts = ({String name, String folder, int size, String version});

/// What the sort button offers over an apps-manager table.
///
/// A fixed list, which is the point: the sheet offers the same four sorts at
/// every width, so it cannot be derived from the laid-out columns - two of
/// them are dropped on a phone, and a control that comes and goes with the
/// window is one a user cannot learn. `sortOptionsFor` is the archive's way
/// round the same problem and does not fit here: it prepends a folder entry
/// for a table whose name and folder share one cell, which at the widths
/// where this table *has* a folder column would offer that sort twice.
///
/// The keys are the comparator's own, which is why this list lives beside
/// it.
List<SortOption> appsSortOptions() {
  final s = l10n;
  return [
    (key: 'name', label: s.sortByName),
    (key: 'folder', label: s.sortByFolder),
    (key: 'version', label: s.colVersion),
    (key: 'size', label: s.colSize),
  ];
}

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

  /// The toolbar's sort button over this state.
  ///
  /// Here rather than at each page so the two apps-manager tables cannot
  /// drift into offering different sorts, and so what the button offers can
  /// be read on its own: `AppsManagerPage` reaches `AppsBackend.instance` and
  /// primes a device and an update registry in `initState`, and the install
  /// page wants the ATP catalog, so neither is a widget a test pumps for the
  /// sake of one argument.
  SortControl control(ValueChanged<String> onSort) =>
      (key: key, asc: asc, opts: appsSortOptions(), onSort: onSort);

  int compare(AppsRowFacts a, AppsRowFacts b) {
    // Not `asc ? cmp : -cmp` like the rest: a folder sort turned around is
    // `ORDER BY folder DESC, name ASC`, because the name is a tiebreak nobody
    // picked a direction for. Negating the pair handed every folder's apps
    // back in reverse, which also made this table disagree with the archive
    // about what the same gesture means - #312 settled that for the archive,
    // #314 is this table catching up.
    //
    // `folderSortKey` with it, and that half is **not** a bug being fixed
    // here: an apps folder is one segment today, because the device walk is
    // one level only and the install table's folder is a catalog field, and
    // for a string with no `/` the key only lowercases. What it buys is that
    // this table stops holding a second answer to a question the shared layer
    // has already answered - `folder_sort.dart`'s own charter - so a nested
    // folder could not split a subtree if the walk ever grew one.
    if (key == 'folder') {
      return compareFolderThenName(
        folderSortKey(a.folder),
        a.name.toLowerCase(),
        folderSortKey(b.folder),
        b.name.toLowerCase(),
        asc,
      );
    }
    final int cmp;
    switch (key) {
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
  // Each has to hold its uppercased label, the 8px of padding inside a header
  // cell and the 12px sort arrow the active column carries. "VERSION" renders
  // at 74.2, so 74 was 20 short of what it needed and "SIZE" at 42.4 had 1.6
  // to spare - close enough that a slightly wider font metric would have taken
  // it too. The header ellipsizes now rather than overflowing, so these are
  // what keeps the English labels whole rather than what keeps the layout
  // legal.
  const sizeW = 72.0;
  const versionW = 96.0;
  const folderW = 118.0;
  final showFolder = avail > 460;
  final showVersion = avail > 360;
  final fixed =
      sizeW + (showFolder ? folderW : 0) + (showVersion ? versionW : 0);
  final nameW = (avail - fixed - 24)
      .clamp(kNameMinWidth, double.infinity)
      .toDouble();
  return [
    (col: ArchiveCol(l10n.colNameFolder, 0, sortKey: 'name'), width: nameW),
    if (showFolder)
      (
        col: ArchiveCol(l10n.colFolder, folderW, sortKey: 'folder'),
        width: folderW,
      ),
    if (showVersion)
      (
        col: ArchiveCol(
          l10n.colVersion,
          versionW,
          sortKey: 'version',
          right: true,
        ),
        width: versionW,
      ),
    (
      col: ArchiveCol(l10n.colSize, sizeW, sortKey: 'size', right: true),
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
