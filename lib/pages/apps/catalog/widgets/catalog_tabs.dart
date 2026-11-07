import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/catalog_api.dart' show CatalogFamily;
import '../controller.dart' show CatalogSearchView;
import 'category_chip.dart' show catalogFamilyIcon, catalogFamilyLabel;

/// One place the catalog can show: everything at once, a family, or authors.
@immutable
class CatalogDestination {
  const CatalogDestination.family(CatalogFamily this.family) : view = null;
  const CatalogDestination.view(CatalogSearchView this.view) : family = null;

  final CatalogFamily? family;
  final CatalogSearchView? view;

  static final List<CatalogDestination> all = [
    const CatalogDestination.view(CatalogSearchView.everything),
    for (final family in CatalogFamily.values)
      CatalogDestination.family(family),
    const CatalogDestination.view(CatalogSearchView.authors),
  ];

  static int indexOf({
    required CatalogSearchView? view,
    required CatalogFamily family,
  }) =>
      all.indexWhere((d) => view != null ? d.view == view : d.family == family);
}

/// The catalog's sections as M3 primary tabs, in the pinned header where a
/// page title would be. Tabs are scrollable and start-aligned, so a new
/// family the server adds becomes one more tab instead of another row of
/// chips.
///
/// [trailing] sits at the end of the same row - the header actions and the
/// sort control, in reach however far the list is scrolled.
class CatalogTabs extends StatefulWidget implements PreferredSizeWidget {
  const CatalogTabs({
    super.key,
    required this.family,
    required this.view,
    required this.onSelect,
    this.padding = 16,
    this.trailing,
  });

  final CatalogFamily family;
  final CatalogSearchView? view;
  final ValueChanged<CatalogDestination> onSelect;

  /// The page gutter; the first tab's label lines up with the title.
  final double padding;

  /// Brings its own end padding: an icon button lines up with the app bar
  /// actions above it, an outlined chip with the gutter.
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  State<CatalogTabs> createState() => _CatalogTabsState();
}

class _CatalogTabsState extends State<CatalogTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: CatalogDestination.all.length,
    initialIndex: _index,
    vsync: this,
  );

  int get _index =>
      CatalogDestination.indexOf(view: widget.view, family: widget.family);

  @override
  void didUpdateWidget(CatalogTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _index;
    if (index >= 0 && index != _tabs.index) _tabs.animateTo(index);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final trailing = widget.trailing;
    final tabs = Semantics(
      container: true,
      label: s.catalogSectionsLabel,
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        // The tab's own 16dp label padding sits inside this, so the first
        // label starts on the gutter.
        padding: EdgeInsets.symmetric(horizontal: widget.padding - 16),
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        labelColor: colors.accent,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        // One divider under the whole row, trailing control included.
        dividerHeight: 0,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? colors.accent.withValues(alpha: 0.10)
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? colors.accent.withValues(alpha: 0.08)
              : null,
        ),
        onTap: (i) => widget.onSelect(CatalogDestination.all[i]),
        tabs: [
          for (final (i, d) in CatalogDestination.all.indexed)
            _DestinationTab(
              label: _label(context, d),
              asset: _asset(d),
              icon: d.view == CatalogSearchView.everything
                  ? Icons.auto_awesome_mosaic_outlined
                  : null,
              selected: i == _index,
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            // Tabs that scroll under the trailing control fade out instead
            // of being cut off mid-word against it.
            child: trailing == null
                ? tabs
                : ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      colors: const [Colors.white, Colors.transparent],
                      stops: [(bounds.width - 32) / bounds.width, 1],
                    ).createShader(bounds),
                    child: tabs,
                  ),
          ),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : Durations.short4,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                child: child,
              ),
            ),
            child: trailing == null
                ? const SizedBox.shrink()
                : Padding(
                    key: const ValueKey('trailing'),
                    padding: const EdgeInsets.only(left: 8),
                    child: trailing,
                  ),
          ),
        ],
      ),
    );
  }

  static String _label(BuildContext context, CatalogDestination d) {
    final family = d.family;
    if (family != null) return catalogFamilyLabel(context, family);
    return switch (d.view!) {
      CatalogSearchView.everything => context.l10n.catalogScopeAll,
      CatalogSearchView.authors => context.l10n.catalogScopeAuthors,
    };
  }

  static String? _asset(CatalogDestination d) {
    final family = d.family;
    if (family != null) return catalogFamilyIcon(family);
    return d.view == CatalogSearchView.authors
        ? 'assets/ic/fileformat/passport.svg'
        : null;
  }
}

/// Icon and label inline, the M3 layout for tabs that need to stay 48dp.
class _DestinationTab extends StatelessWidget {
  const _DestinationTab({
    required this.label,
    required this.selected,
    this.asset,
    this.icon,
  });

  final String label;
  final bool selected;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = selected ? colors.accent : colors.textSecondary;
    final svg = asset;
    return Tab(
      height: 48,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (svg != null)
            QIcon(asset: svg, color: color, size: 18)
          else if (icon != null)
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
