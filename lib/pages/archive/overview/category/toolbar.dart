import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../../data/category.dart';

class CategoryAppBarTitle extends StatelessWidget {
  const CategoryAppBarTitle({super.key, required this.cat, this.syncFileName});

  final ArchiveCategory cat;
  final String? syncFileName;

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
            syncFileName ?? cat.remoteDir,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(
                alpha: syncFileName != null ? 0.85 : 0.5,
              ),
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
    required this.starredOnly,
    required this.catColor,
    required this.colors,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onStarredToggle,
    this.showStar = true,
  });

  final TextEditingController searchCtrl;
  final String query;
  final String? filterVal;
  final List<String> filterOpts;
  final bool starredOnly;
  final Color catColor;
  final QAppColors colors;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onFilterChanged;
  final VoidCallback onStarredToggle;

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
                  hintText: 'Search…',
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
            if (showStar) ...[
              const SizedBox(width: 4),
              _StarBtn(active: starredOnly, onToggle: onStarredToggle),
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
              '$count selected',
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
                    allSelected ? 'None' : 'All',
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
        decoration: BoxDecoration(
          color: filled
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(9),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.26)),
        ),
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
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(9),
          border: active
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.26)),
        ),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Filter',
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
                children: [
                  ListTile(
                    title: Text(
                      'All',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    trailing: selected == null
                        ? Icon(Icons.check_rounded, color: catColor)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      onChanged(null);
                    },
                  ),
                  for (final o in opts)
                    ListTile(
                      title: Text(
                        o,
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      trailing: selected == o
                          ? Icon(Icons.check_rounded, color: catColor)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        onChanged(o);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
            border: active
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.26)),
          ),
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
