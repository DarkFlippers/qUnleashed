import 'package:flutter/material.dart';

import '../../services/localization/l10n.dart';
import '../icon.dart';
import '../../theme/theme.dart';
import '../archive/category.dart';
import 'columns.dart';

/// Everything the toolbar's sort button needs: what it offers, which sort is
/// in force and which way it runs, and where to report a pick.
typedef SortControl = ({
  String key,
  bool asc,
  List<SortOption> opts,
  ValueChanged<String> onSort,
});

/// Title inset for the category-style app bars. A pushed page has a back
/// button separating the title from the edge, so it keeps zero; a page hosted
/// as a root by the desktop rail has no leading widget and needs the standard
/// spacing instead. Reads the same flag [AppBar] itself uses to decide on that
/// button: it describes this page's own route, so a dialog opened over the page
/// cannot flip the spacing under it.
double categoryTitleSpacing(BuildContext context) =>
    (ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
    ? 0
    : NavigationToolbar.kMiddleSpacing;

class CategoryAppBarTitle extends StatelessWidget {
  const CategoryAppBarTitle({super.key, required this.cat});

  final ArchiveCategory cat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        QIcon(asset: cat.asset, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(
          cat.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            cat.remoteDir,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared pill height so the count badge and sync button line up exactly.
const double kCategoryPillHeight = 24;

class CategoryCountBadge extends StatelessWidget {
  const CategoryCountBadge({
    super.key,
    required this.filtered,
    required this.total,
  });

  final int filtered;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Center(
        child: Container(
          height: kCategoryPillHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
          ),
          child: Text(
            filtered < total ? '$filtered/$total' : '$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class CategorySyncButton extends StatefulWidget {
  const CategorySyncButton({
    super.key,
    required this.syncing,
    required this.enabled,
    required this.catColor,
    required this.onTap,
  });

  final bool syncing;
  final bool enabled;
  final Color catColor;
  final VoidCallback onTap;

  @override
  State<CategorySyncButton> createState() => _CategorySyncButtonState();
}

class _CategorySyncButtonState extends State<CategorySyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _spin.repeat();
  }

  @override
  void didUpdateWidget(CategorySyncButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncing && !oldWidget.syncing) {
      _spin.repeat();
    } else if (!widget.syncing && oldWidget.syncing) {
      _spin
          .animateTo(
            1,
            duration: Duration(milliseconds: (900 * (1 - _spin.value)).round()),
          )
          .whenComplete(() {
            if (mounted) _spin.reset();
          });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.syncing;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Center(
        child: GestureDetector(
          onTap: (widget.enabled && !widget.syncing) ? widget.onTap : null,
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.45,
            child: Container(
              height: kCategoryPillHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: active
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: 0.26)),
              ),
              child: RotationTransition(
                turns: _spin,
                child: Icon(
                  Icons.sync_rounded,
                  size: 14,
                  color: active ? widget.catColor : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryToolbar extends StatelessWidget {
  const CategoryToolbar({
    super.key,
    required this.searchCtrl,
    required this.query,
    required this.filterVal,
    required this.filterOpts,
    required this.catColor,
    required this.colors,
    required this.onQueryChanged,
    required this.onFilterChanged,
    this.sort,
    this.starredOnly = false,
    this.onStarredToggle,
    this.showStar = true,
  });

  final TextEditingController searchCtrl;
  final String query;
  final String? filterVal;
  final List<String> filterOpts;

  /// The sort button, or null for no button at all.
  ///
  /// Every table that has one passes it now, the two apps-manager tables
  /// included (#314). Their folder is a column of its own with a header to
  /// tap, so the sheet adds nothing above the 460 logical pixels of *table*
  /// width `appsTableColumns` needs to show that column - and below it the
  /// column and its header both go, which left those two tables with #122's
  /// original complaint and no way at all to reach a folder sort on a phone.
  /// The window is wider than that figure wherever a rail or page padding
  /// sits beside the table.
  ///
  /// Offered at every width rather than only the narrow ones, which is what
  /// the archive does: a button that comes and goes with the window is a
  /// control a user cannot learn, and at a wide width it agrees with the
  /// header it duplicates.
  ///
  /// One parameter because the four move together and mean nothing apart: a
  /// key with no options behind it, or options with nothing to report them to,
  /// is a button that silently does not appear.
  ///
  /// `onSort` takes the key the user picked, exactly as a column header tap
  /// does, and picking the one already in force turns it around. One handler
  /// for the two surfaces keeps them from drifting into disagreeing about what
  /// a second tap means.
  final SortControl? sort;

  final bool starredOnly;
  final Color catColor;
  final QAppColors colors;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onFilterChanged;
  final VoidCallback? onStarredToggle;

  /// Whether to show the "starred only" toggle. Off in the deleted table, where
  /// favouriting does not apply.
  final bool showStar;

  static const double _h = 36;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: catColor,
      padding: const EdgeInsets.fromLTRB(10, 0, 8, 10),
      child: SizedBox(
        height: _h,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: searchCtrl,
                onChanged: onQueryChanged,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: context.l10n.searchHint,
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.75),
                    size: 17,
                  ),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.75),
                            size: 15,
                          ),
                          onPressed: () {
                            searchCtrl.clear();
                            onQueryChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.16),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.4,
                    ),
                  ),
                  isDense: true,
                ),
              ),
            ),
            if (filterOpts.isNotEmpty) ...[
              const SizedBox(width: 6),
              _FilterBtn(
                selected: filterVal,
                opts: filterOpts,
                catColor: catColor,
                colors: colors,
                onChanged: onFilterChanged,
              ),
            ],
            if (sort case final sort?) ...[
              const SizedBox(width: 6),
              _SortBtn(sort: sort, catColor: catColor, colors: colors),
            ],
            if (showStar && onStarredToggle != null) ...[
              const SizedBox(width: 4),
              _StarBtn(active: starredOnly, onToggle: onStarredToggle!),
            ],
          ],
        ),
      ),
    );
  }
}

class CategorySelectionToolbar extends StatelessWidget {
  const CategorySelectionToolbar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.catColor,
    required this.onClose,
    required this.onToggleAll,
    required this.onActions,
  });

  final int count;
  final bool allSelected;
  final Color catColor;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final VoidCallback onActions;

  static const double _h = 36;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: catColor,
      padding: const EdgeInsets.fromLTRB(6, 0, 8, 10),
      child: SizedBox(
        height: _h,
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              context.l10n.selectedCount(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _PillButton(
              onTap: onToggleAll,
              filled: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    allSelected
                        ? context.l10n.selectNone
                        : context.l10n.selectAll,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _PillButton(
              onTap: onActions,
              filled: true,
              child: Icon(Icons.more_horiz_rounded, size: 18, color: catColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chrome the toolbars' pill-shaped buttons wear: filled white when the
/// control is doing something, outlined over the category colour when it is
/// not.
///
/// Five buttons wear it - the selection toolbar's two, the filter, the sort
/// and the star - through widget classes that had each spelled the same three
/// properties out, so the alpha values had to be kept in step by eye.
///
/// Not the search field, which is an `InputDecoration` carrying its own
/// `0.16` fill and `0.28` border. Those are already a shade off these, and
/// whether that is deliberate is older than this function.
BoxDecoration pillDecoration({required bool active}) => BoxDecoration(
  color: Colors.white.withValues(alpha: active ? 0.88 : 0.18),
  borderRadius: BorderRadius.circular(9),
  border: active
      ? null
      : Border.all(color: Colors.white.withValues(alpha: 0.26)),
);

/// The sheet the filter and the sort buttons both open: a titled card over the
/// page holding one tappable row per choice.
///
/// [rows] is built against the sheet's own context, so a row closes it with
/// that context rather than the one the button was tapped in.
void showPickerSheet(
  BuildContext context, {
  required QAppColors colors,
  required String title,
  required List<Widget> Function(BuildContext sheetContext) rows,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(height: 1, color: colors.divider),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: rows(sheetContext),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One choice in a [showPickerSheet], which closes the sheet and reports.
/// [trailing] marks the choice in force, and is null for the rest.
Widget pickerRow({
  required BuildContext sheetContext,
  required QAppColors colors,
  required String label,
  required Widget? trailing,
  required VoidCallback onPick,
}) {
  return ListTile(
    title: Text(label, style: TextStyle(color: colors.textPrimary)),
    trailing: trailing,
    onTap: () {
      Navigator.pop(sheetContext);
      onPick();
    },
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.onTap,
    required this.filled,
    required this.child,
  });

  final VoidCallback onTap;
  final bool filled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: pillDecoration(active: filled),
        child: child,
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  const _FilterBtn({
    required this.selected,
    required this.opts,
    required this.catColor,
    required this.colors,
    required this.onChanged,
  });

  final String? selected;
  final List<String> opts;
  final Color catColor;
  final QAppColors colors;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = selected != null;
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: pillDecoration(active: active),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: active ? catColor : Colors.white.withValues(alpha: 0.8),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Text(
                selected!,
                style: TextStyle(
                  color: catColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showPickerSheet(
      context,
      colors: colors,
      title: context.l10n.filterTitle,
      rows: (sheetContext) => [
        pickerRow(
          sheetContext: sheetContext,
          colors: colors,
          label: context.l10n.filterAll,
          trailing: selected == null
              ? Icon(Icons.check_rounded, color: catColor)
              : null,
          onPick: () => onChanged(null),
        ),
        for (final o in opts)
          pickerRow(
            sheetContext: sheetContext,
            colors: colors,
            label: o,
            trailing: selected == o
                ? Icon(Icons.check_rounded, color: catColor)
                : null,
            onPick: () => onChanged(o),
          ),
      ],
    );
  }
}

/// Opens the sheet that picks how the list is ordered.
///
/// The sheet exists because the folder sort has no column header to tap, but
/// it carries every sort the table offers, so the choice is one place rather
/// than two halves of one.
class _SortBtn extends StatelessWidget {
  const _SortBtn({
    required this.sort,
    required this.catColor,
    required this.colors,
  });

  final SortControl sort;
  final Color catColor;
  final QAppColors colors;

  /// Name ascending is the order a page opens in, so it is the one the button
  /// does not announce. Anything else and the lit pill says why the list is in
  /// the order it is in, without opening the sheet to find out.
  bool get _active => sort.key != 'name' || !sort.asc;

  /// Which way the list runs. The button has room for this and not for the
  /// field, which the sheet names instead.
  Widget _arrow({required double size}) => Icon(
    sort.asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
    size: size,
    color: catColor,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: pillDecoration(active: _active),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_rounded,
              size: 15,
              color: _active ? catColor : Colors.white.withValues(alpha: 0.8),
            ),
            if (_active) ...[const SizedBox(width: 2), _arrow(size: 11)],
          ],
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    showPickerSheet(
      context,
      colors: colors,
      title: context.l10n.sortTitle,
      rows: (sheetContext) => [
        for (final o in sort.opts)
          pickerRow(
            sheetContext: sheetContext,
            colors: colors,
            label: o.label,
            trailing: sort.key == o.key ? _arrow(size: 18) : null,
            onPick: () => sort.onSort(o.key),
          ),
      ],
    );
  }
}

class _StarBtn extends StatelessWidget {
  const _StarBtn({required this.active, required this.onToggle});

  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: pillDecoration(active: active),
          child: Icon(
            active ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 17,
            color: active
                ? Colors.amber.shade700
                : Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
