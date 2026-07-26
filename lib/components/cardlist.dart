import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/theme.dart';

const double kGroupedOuterRadius = 12;
const double kGroupedInnerRadius = 4;
const double kGroupedGap = 3;
const double kGroupedHorizontalPadding = 14;
const EdgeInsets kGroupedCardPadding = EdgeInsets.fromLTRB(12, 6, 8, 6);
const double kGroupedGridMaxExtent = 104;
const double kGroupedGridTileHeight = 104;
const double kGroupedTitleSize = 12.5;
const FontWeight kGroupedTitleWeight = FontWeight.w600;
const EdgeInsets kGroupedTitlePadding = EdgeInsets.fromLTRB(12, 2, 12, 6);

class GroupedCardCorners extends InheritedWidget {
  const GroupedCardCorners({
    super.key,
    required this.radius,
    required super.child,
  });

  final BorderRadius radius;

  static const outer = Radius.circular(kGroupedOuterRadius);
  static const inner = Radius.circular(kGroupedInnerRadius);

  static BorderRadius of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GroupedCardCorners>()
          ?.radius ??
      const BorderRadius.all(outer);

  @override
  bool updateShouldNotify(GroupedCardCorners oldWidget) =>
      radius != oldWidget.radius;
}

class GroupedCard extends StatelessWidget {
  const GroupedCard({
    super.key,
    this.onTap,
    this.padding = kGroupedCardPadding,
    this.background,
    required this.child,
  });

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Widget? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final content = InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    );
    return Material(
      color: colors.card,
      borderRadius: GroupedCardCorners.of(context),
      clipBehavior: Clip.antiAlias,
      child: background == null
          ? content
          : Stack(children: [background!, content]),
    );
  }
}

Widget _groupTitle(BuildContext context, String? title, Widget? header) {
  if (header != null) return header;
  if (title == null) return const SizedBox.shrink();
  return Padding(
    padding: kGroupedTitlePadding,
    child: Text(
      title,
      style: TextStyle(
        fontSize: kGroupedTitleSize,
        fontWeight: kGroupedTitleWeight,
        color: context.appColors.textSecondary,
      ),
    ),
  );
}

class GroupedCardList<T> extends StatelessWidget {
  const GroupedCardList({
    super.key,
    this.title,
    this.header,
    required this.items,
    required this.itemBuilder,
    this.onTap,
    this.cardPadding = kGroupedCardPadding,
    this.backgroundBuilder,
    this.wrapItems = true,
  });

  final String? title;
  final Widget? header;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final VoidCallback? Function(T item)? onTap;
  final EdgeInsetsGeometry cardPadding;
  final Widget? Function(T item)? backgroundBuilder;

  final bool wrapItems;

  @override
  Widget build(BuildContext context) {
    final last = items.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGroupedHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null || title != null)
            _groupTitle(context, title, header),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: kGroupedGap),
            GroupedCardCorners(
              radius: BorderRadius.vertical(
                top: i == 0
                    ? GroupedCardCorners.outer
                    : GroupedCardCorners.inner,
                bottom: i == last
                    ? GroupedCardCorners.outer
                    : GroupedCardCorners.inner,
              ),
              child: wrapItems
                  ? GroupedCard(
                      onTap: onTap?.call(items[i]),
                      padding: cardPadding,
                      background: backgroundBuilder?.call(items[i]),
                      child: itemBuilder(context, items[i]),
                    )
                  : itemBuilder(context, items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class GroupedCardGrid<T> extends StatelessWidget {
  const GroupedCardGrid({
    super.key,
    this.title,
    this.header,
    required this.items,
    required this.itemBuilder,
    this.onTap,
    this.backgroundBuilder,
    this.cardPadding = kGroupedCardPadding,
    this.maxCrossAxisExtent = kGroupedGridMaxExtent,
    this.mainAxisExtent = kGroupedGridTileHeight,
    this.crossAxisCount,
    this.spacing = kGroupedGap,
    this.wrapItems = true,
  });

  final String? title;
  final Widget? header;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final VoidCallback? Function(T item)? onTap;
  final Widget? Function(T item)? backgroundBuilder;
  final EdgeInsetsGeometry cardPadding;
  final double maxCrossAxisExtent;

  /// Fixed cell height. When null the row sizes to the tallest cell
  /// ([IntrinsicHeight]) and cells stretch to match — use this for a few
  /// content-sized cards; keep a value for large uniform tile grids.
  final double? mainAxisExtent;

  /// Forces the column count, ignoring [maxCrossAxisExtent] when set.
  final int? crossAxisCount;
  final double spacing;
  final bool wrapItems;

  Widget _cell(BuildContext context, T item) {
    if (!wrapItems) return itemBuilder(context, item);
    return GroupedCard(
      onTap: onTap?.call(item),
      padding: cardPadding,
      background: backgroundBuilder?.call(item),
      child: itemBuilder(context, item),
    );
  }

  BorderRadius _cellRadius(int index, int columns, int total) {
    final col = index % columns;
    final top = index - columns < 0;
    final bottom = index + columns >= total;
    final left = col == 0;
    final right = col == columns - 1 || index + 1 >= total;
    Radius corner(bool a, bool b) =>
        (a && b) ? GroupedCardCorners.outer : GroupedCardCorners.inner;
    return BorderRadius.only(
      topLeft: corner(top, left),
      topRight: corner(top, right),
      bottomLeft: corner(bottom, left),
      bottomRight: corner(bottom, right),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGroupedHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null || title != null)
            _groupTitle(context, title, header),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns =
                  crossAxisCount ??
                  math.max(1, (width / (maxCrossAxisExtent + spacing)).ceil());
              final fixedHeight = mainAxisExtent;
              final rows = <Widget>[];
              for (var start = 0; start < items.length; start += columns) {
                final cells = <Widget>[];
                for (var c = 0; c < columns; c++) {
                  if (c > 0) cells.add(SizedBox(width: spacing));
                  final index = start + c;
                  Widget cell;
                  if (index < items.length) {
                    cell = GroupedCardCorners(
                      radius: _cellRadius(index, columns, items.length),
                      child: _cell(context, items[index]),
                    );
                    if (fixedHeight != null) {
                      cell = SizedBox(height: fixedHeight, child: cell);
                    }
                  } else {
                    cell = const SizedBox.shrink();
                  }
                  cells.add(Expanded(child: cell));
                }
                if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
                final row = Row(
                  crossAxisAlignment: fixedHeight == null
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.center,
                  children: cells,
                );
                rows.add(fixedHeight == null ? IntrinsicHeight(child: row) : row);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              );
            },
          ),
        ],
      ),
    );
  }
}
