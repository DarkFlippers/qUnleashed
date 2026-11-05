import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'columns.dart';
import 'table.dart';
import 'toolbar.dart';

/// The body of an archive overview page: a pull-to-refresh over either an
/// empty view or a column header with its rows under it.
///
/// #404, and the three pages had it written out three times. What differed was
/// the column set, the accent colour, what a refresh runs, the empty view and
/// the row - all of which are arguments here. What did *not* differ, and is
/// the reason this exists, is the shape around them:
///
///  * the available width for the columns is the layout's width **less the
///    selection indicator**, which is otherwise a piece of arithmetic each
///    page has to remember when it grows a selection;
///  * an empty list is the page's empty view inside a scroll view with
///    `AlwaysScrollableScrollPhysics`, which is what keeps the pull-to-refresh
///    reachable with nothing on screen to drag; the height forced to the
///    viewport is what makes that view fill the screen rather than sit in a
///    strip at the top;
///  * the header is outside the scrollable and the rows are inside it, so the
///    column titles stay put.
///
/// [itemBuilder] is handed the laid-out columns, because they are only known
/// inside the layout and every row needs them. It is **not** handed a
/// `BuildContext`: the pages build their rows against the page's context on
/// purpose - a row's context dies with the row, and `KeyActionsSheet` carries
/// the one it is given across awaits and tests `mounted` on it, so a sheet
/// opened with a row's context goes quiet the moment the row leaves the list
/// (a failed delete, a restore, a rename). That was #110, and this signature
/// is why it cannot come back here.
///
/// `AppsTable` in `pages/apps/manager/widgets/` is the same shape for a
/// different row type, and is not folded in here: it has no empty branch - so
/// pull-to-refresh is unreachable on an empty apps list, which is the defect
/// the second bullet above describes - and its header sits *inside* the
/// `RefreshIndicator` rather than outside it. Settling those two is its own
/// change. The browser's table half is nearly this too, blocked only by its
/// own header type, a second width to subtract and the FAB's list padding.
class ArchiveKeyTable extends StatelessWidget {
  const ArchiveKeyTable({
    super.key,
    required this.columns,
    required this.sort,
    required this.selectionMode,
    required this.accent,
    required this.onRefresh,
    required this.empty,
    required this.itemCount,
    required this.itemBuilder,
  });

  /// The columns to show, given the width left after the selection indicator.
  final List<SizedColumn> Function(double width) columns;

  /// Which sort is in force and where to report a pick. The toolbar's own
  /// record, `opts` and all: one of those per page rather than two that can
  /// drift into disagreeing about what a second tap means.
  final SortControl sort;

  /// Whether a selection is up: it costs the columns
  /// [kSelectionIndicatorWidth] and puts a blank of that width in the header,
  /// under which each row shows its own tick.
  final bool selectionMode;

  /// The refresh spinner's colour, which is the page's header colour.
  final Color accent;

  /// Returned rather than started, which [RefreshIndicator] requires: it holds
  /// its spinner until the future settles, so a body that starts the work and
  /// returns immediately flashes the spinner and lies. #219.
  final Future<void> Function() onRefresh;

  /// Shown instead of the table when [itemCount] is zero.
  ///
  /// A callback, because the pages build theirs out of several `l10n` lookups
  /// and a list state, and a table with rows in it rebuilds on every transfer
  /// tick - roughly eight times a second - with nowhere to put the result.
  final Widget Function() empty;

  final int itemCount;

  /// Builds row [index]. See the note above about the missing `BuildContext`.
  final Widget Function(int index, List<SizedColumn> cols) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = columns(
          constraints.maxWidth - (selectionMode ? kSelectionIndicatorWidth : 0),
        );

        return RefreshIndicator(
          color: accent,
          displacement: 15,
          onRefresh: onRefresh,
          child: itemCount == 0
              ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: empty(),
                  ),
                )
              : Column(
                  children: [
                    ArchiveColumnHeader(
                      cols: cols,
                      sortKey: sort.key,
                      sortAsc: sort.asc,
                      onSort: sort.onSort,
                      colors: colors,
                      selectionMode: selectionMode,
                    ),
                    Expanded(
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        itemCount: itemCount,
                        itemBuilder: (_, i) => itemBuilder(i, cols),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
