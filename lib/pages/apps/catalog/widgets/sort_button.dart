import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_api.dart';

/// What the list is ordered by. The labels name the field only - "Update
/// date", never "Recently updated" - so no field ever contradicts the order
/// picked next to it. Only the dates have a second direction.
enum _SortField {
  popularWeek(Icons.local_fire_department_outlined),
  popular(Icons.download_outlined),
  updated(Icons.update_rounded),
  released(Icons.event_outlined),
  name(Icons.sort_by_alpha_rounded);

  const _SortField(this.icon);
  final IconData icon;

  static _SortField of(AppsSort sort) => switch (sort) {
    AppsSort.popularWeek => popularWeek,
    AppsSort.popular => popular,
    AppsSort.newUpdates || AppsSort.oldUpdates => updated,
    AppsSort.newReleases || AppsSort.oldReleases => released,
    AppsSort.alphabetical => name,
  };

  bool get dated => this == updated || this == released;

  /// Whether the server can order by it at all.
  bool availableOn({required bool v1}) =>
      v1 || (this != popularWeek && this != popular);

  AppsSort sort({required bool oldestFirst}) => switch (this) {
    popularWeek => AppsSort.popularWeek,
    popular => AppsSort.popular,
    updated => oldestFirst ? AppsSort.oldUpdates : AppsSort.newUpdates,
    released => oldestFirst ? AppsSort.oldReleases : AppsSort.newReleases,
    name => AppsSort.alphabetical,
  };

  String label(L10n s) => switch (this) {
    popularWeek => s.sortPopularWeek,
    popular => s.sortPopular,
    updated => s.sortFieldUpdated,
    released => s.sortFieldReleased,
    name => s.sortFieldName,
  };
}

/// The order every catalog list opens with.
const AppsSort kDefaultCatalogSort = AppsSort.newUpdates;

bool _oldestFirst(AppsSort sort) =>
    sort == AppsSort.oldUpdates || sort == AppsSort.oldReleases;

/// The order as one phrase, for the button: "Recently updated", "Oldest".
String sortLabel(L10n s, AppsSort sort) => switch (sort) {
  AppsSort.newUpdates => s.sortNewUpdates,
  AppsSort.newReleases => s.sortNewReleases,
  AppsSort.oldUpdates => s.sortOldUpdates,
  AppsSort.oldReleases => s.sortOldReleases,
  AppsSort.alphabetical => s.sortAlphabetical,
  AppsSort.popular => s.sortPopular,
  AppsSort.popularWeek => s.sortPopularWeek,
};

/// M3 menu and list dividers: 1dp of outline-variant with 8dp above and
/// below. The theme's own outline variant is unset and falls back to the
/// foreground colour, so it is always given here.
Widget _divider(BuildContext context, {double indent = 0}) => Divider(
  height: 16,
  thickness: 1,
  indent: indent,
  endIndent: indent,
  color: context.appColors.divider,
);

/// The catalog's sort control. It reads as a filter, not as an action: an
/// outlined 32dp chip naming the current order. The choice opens where M3
/// puts it for the window: a bottom sheet on a phone, a menu under the
/// button on anything wider. Either way it is two decisions - the field,
/// then, for a date, which end comes first.
class CatalogSortButton extends StatefulWidget {
  const CatalogSortButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.v1 = true,
  });

  final AppsSort value;
  final ValueChanged<AppsSort> onChanged;

  /// An icon button only, for headers with no room for the label.
  final bool compact;

  /// Popularity orders exist on v1 servers only.
  final bool v1;

  @override
  State<CatalogSortButton> createState() => _CatalogSortButtonState();
}

class _CatalogSortButtonState extends State<CatalogSortButton> {
  final MenuController _menu = MenuController();

  static const double _sheetBreakpoint = 600;

  List<_SortField> get _fields => [
    for (final f in _SortField.values)
      if (f.availableOn(v1: widget.v1)) f,
  ];

  void _open() {
    if (MediaQuery.sizeOf(context).width < _sheetBreakpoint) {
      _openSheet();
    } else if (_menu.isOpen) {
      _menu.close();
    } else {
      _menu.open();
    }
  }

  Future<void> _openSheet() async {
    final colors = context.appColors;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: colors.card,
      builder: (context) => _SortSheet(
        fields: _fields,
        value: widget.value,
        onChanged: widget.onChanged,
      ),
    );
  }

  Widget _check(bool on) => on
      ? Icon(Icons.check_rounded, size: 20, color: context.appColors.accent)
      : const SizedBox(width: 20);

  Widget _item({
    required IconData icon,
    required String label,
    required bool selected,
    required bool closeOnActivate,
    required VoidCallback onPressed,
  }) {
    final colors = context.appColors;
    return MenuItemButton(
      closeOnActivate: closeOnActivate,
      leadingIcon: Icon(
        icon,
        size: 20,
        color: selected ? colors.accent : colors.textSecondary,
      ),
      trailingIcon: _check(selected),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? colors.accent : colors.textPrimary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    final current = _SortField.of(widget.value);
    final oldestFirst = _oldestFirst(widget.value);
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.card),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        for (final field in _fields)
          _item(
            icon: field.icon,
            label: field.label(s),
            selected: field == current,
            // Picking a date keeps the menu open: its order shows up below.
            closeOnActivate: !field.dated,
            onPressed: () =>
                widget.onChanged(field.sort(oldestFirst: oldestFirst)),
          ),
        if (current.dated) ...[
          _divider(context),
          _item(
            icon: Icons.arrow_downward_rounded,
            label: s.sortNewestFirst,
            selected: !oldestFirst,
            closeOnActivate: true,
            onPressed: () => widget.onChanged(current.sort(oldestFirst: false)),
          ),
          _item(
            icon: Icons.arrow_upward_rounded,
            label: s.catalogSortOldestFirst,
            selected: oldestFirst,
            closeOnActivate: true,
            onPressed: () => widget.onChanged(current.sort(oldestFirst: true)),
          ),
        ],
      ],
      child: widget.compact
          ? IconButton(
              tooltip: '${s.catalogSortTitle}: ${sortLabel(s, widget.value)}',
              // A dot once the order is not the one the catalog opens with,
              // so a changed order is never invisible behind an icon.
              icon: Badge(
                isLabelVisible: widget.value != kDefaultCatalogSort,
                smallSize: 6,
                backgroundColor: colors.accent,
                child: Icon(Icons.sort_rounded, color: colors.textPrimary),
              ),
              onPressed: _open,
            )
          : _SortChip(
              label: current.label(s),
              icon: !current.dated
                  ? Icons.swap_vert_rounded
                  : oldestFirst
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              semanticsLabel:
                  '${s.catalogSortTitle}: ${sortLabel(s, widget.value)}',
              onTap: _open,
            ),
    );
  }
}

/// M3 filter chip geometry (32dp, 8dp corners, outline) with a trailing
/// dropdown arrow: the "chip that opens a menu" Play and Gmail use for sort.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  /// The field reads in the label; the direction of a date in this icon.
  final String label;
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: colors.divider),
    );
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        // The chip is drawn 32dp tall; the hit area keeps the 48dp minimum.
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Material(
            color: Colors.transparent,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: colors.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({
    required this.fields,
    required this.value,
    required this.onChanged,
  });

  final List<_SortField> fields;
  final AppsSort value;
  final ValueChanged<AppsSort> onChanged;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late AppsSort _value = widget.value;

  void _apply(AppsSort sort) {
    setState(() => _value = sort);
    widget.onChanged(sort);
  }

  void _pick(_SortField field) {
    _apply(field.sort(oldestFirst: _oldestFirst(_value)));
    // Nothing else to decide for a field with one direction.
    if (!field.dated) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    final current = _SortField.of(_value);
    final oldestFirst = _oldestFirst(_value);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              s.catalogSortTitle,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          for (final field in widget.fields)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              selected: field == current,
              selectedColor: colors.accent,
              selectedTileColor: colors.accent.withValues(alpha: 0.08),
              iconColor: colors.textSecondary,
              textColor: colors.textPrimary,
              leading: Icon(field.icon),
              title: Text(
                field.label(s),
                style: TextStyle(
                  fontWeight: field == current
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              trailing: field == current
                  ? Icon(Icons.check_rounded, color: colors.accent)
                  : null,
              onTap: () => _pick(field),
            ),
          AnimatedSize(
            duration: reduceMotion ? Duration.zero : Durations.medium2,
            curve: Easing.emphasizedDecelerate,
            alignment: Alignment.topCenter,
            child: current.dated
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _divider(context, indent: 24),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                        child: Text(
                          s.sortOrderTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _OrderButtons(
                          oldestFirst: oldestFirst,
                          onChanged: (old) =>
                              _apply(current.sort(oldestFirst: old)),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Newest or oldest first: one of two, always one - an M3 segmented button.
class _OrderButtons extends StatelessWidget {
  const _OrderButtons({required this.oldestFirst, required this.onChanged});

  final bool oldestFirst;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    return SegmentedButton<bool>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      selected: {oldestFirst},
      onSelectionChanged: (v) => onChanged(v.single),
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: colors.divider)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textPrimary,
        ),
        overlayColor: WidgetStatePropertyAll(
          colors.accent.withValues(alpha: 0.08),
        ),
      ),
      segments: [
        ButtonSegment(
          value: false,
          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
          label: Text(s.sortNewestFirst),
        ),
        ButtonSegment(
          value: true,
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          label: Text(s.catalogSortOldestFirst),
        ),
      ],
    );
  }
}
