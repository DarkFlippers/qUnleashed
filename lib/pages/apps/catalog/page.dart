import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import 'widgets/mode_badge.dart';
import 'widgets/states.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import '../../../components/notification.dart';
import '../data/apps_backend.dart';
import '../data/catalog_api.dart'
    show AppsSort, CatalogFamily, CatalogNeedsV1Exception, CatalogSearch;
import '../data/models/author.dart';
import '../data/models/category.dart';
import '../manager/page.dart';
import '../../option/pages/apps.dart';
import 'author_page.dart';
import 'detail_page.dart';
import 'routes.dart';
import 'controller.dart';
import '../data/models/card.dart';
import 'widgets/author_card.dart';
import 'widgets/catalog_grid.dart';
import 'widgets/categories_filter.dart';
import 'widgets/catalog_tabs.dart';
import 'widgets/category_chip.dart';
import 'widgets/layout.dart';
import 'widgets/sort_button.dart';
import 'widgets/submit_dialog.dart';
import 'widgets/floating_actions.dart';

class AppsCatalogPage extends StatefulWidget {
  const AppsCatalogPage({super.key});

  @override
  State<AppsCatalogPage> createState() => _AppsCatalogPageState();
}

enum AppsView { catalog, manager }

class _AppsCatalogPageState extends State<AppsCatalogPage>
    with SingleTickerProviderStateMixin {
  AppsView _view = AppsView.catalog;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: Durations.short4,
    value: 1,
  );
  late final CurvedAnimation _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: Easing.standardDecelerate,
  );
  late final Animation<double> _cover = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(_fadeCurve);

  void _show(AppsView view) {
    if (_view == view) return;
    setState(() => _view = view);
    _fade
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _fadeCurve.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CatalogMode>(
      valueListenable: AppsBackend.instance.mode,
      builder: (context, mode, _) {
        final hasCatalog = AppsCatalogController.showsCatalog(mode);
        return Stack(
          children: [
            IndexedStack(
              index: _view.index,
              sizing: StackFit.expand,
              children: [
                TickerMode(
                  enabled: _view == AppsView.catalog,
                  child: CatalogView(
                    key: ValueKey(AppsBackend.instance.api.server),
                    active: _view == AppsView.catalog,
                    onOpenManager: () => _show(AppsView.manager),
                  ),
                ),
                TickerMode(
                  enabled: _view == AppsView.manager,
                  child: AppsManagerPage(
                    onOpenCatalog: hasCatalog
                        ? () => _show(AppsView.catalog)
                        : null,
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: FadeTransition(
                opacity: _cover,
                child: ColoredBox(
                  color: context.appColors.background,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    this.onOpenManager,
    this.active = true,
    this.openLink,
  });

  final VoidCallback? onOpenManager;
  final bool active;
  final CatalogLink? openLink;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView>
    with SingleTickerProviderStateMixin {
  final AppsCatalogController _ctrl = AppsCatalogController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  bool _managerHandoff = false;

  static const double _toolbarHeight = 48;
  static const double _compactToolbarHeight = 56;

  /// New results enter the way M3 brings in content that replaces unrelated
  /// content: a fade on the emphasized-decelerate curve. The old results are
  /// already gone by then - the controller clears them on every change.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Durations.medium4,
    value: 1,
  );
  late final CurvedAnimation _revealCurve = CurvedAnimation(
    parent: _reveal,
    curve: Easing.emphasizedDecelerate,
  );
  bool _hadResults = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _ctrl.addListener(_onResults);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.initialize();
      final link = widget.openLink;
      final family = link?.family;
      if (link == null) return;
      if (family == null) {
        openAuthorPage(context, AppAuthor(id: link.id, name: link.id));
      } else {
        openAppDetail(
          context,
          controller: _ctrl,
          alias: link.id,
          family: family,
        );
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _ctrl.loadMore();
    }
  }

  bool get _hasResults => switch (_ctrl.searchView) {
    null =>
      _ctrl.apps.isNotEmpty &&
          !(_ctrl.categoriesLoading && _ctrl.categories.isEmpty),
    CatalogSearchView.authors => _ctrl.authors.isNotEmpty,
    CatalogSearchView.everything => switch (_ctrl.searchResult) {
      null => false,
      final result =>
        result.authors.isNotEmpty ||
            CatalogFamily.values.any((f) => result.itemsOf(f).isNotEmpty),
    },
  };

  void _onResults() {
    final has = _hasResults;
    if (has && !_hadResults && !_reduceMotion) _reveal.forward(from: 0);
    _hadResults = has;
  }

  void _openAssembler() {
    openRoute(context, AppRoute.assemblerConsole);
  }

  void _openSearch() => setState(() => _searchOpen = true);

  void _closeSearch() {
    setState(() => _searchOpen = false);
    _searchCtrl.clear();
    _ctrl.closeSearch();
  }

  /// A new section, category or order is a new list: it starts at the top.
  /// The old offset otherwise survived the swap and left the chips half
  /// under the pinned header.
  void _toTop() {
    if (_scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
  }

  void _selectCategory(AppCategory? category) {
    _toTop();
    _ctrl.selectCategory(category);
  }

  void _selectSort(AppsSort sort) {
    _toTop();
    _ctrl.selectSort(sort);
  }

  void _select(CatalogDestination destination) {
    _toTop();
    final family = destination.family;
    if (family != null) {
      guarded('[AppsCatalog] select section', () => _ctrl.selectFamily(family));
    } else {
      _ctrl.selectSearchView(destination.view!);
    }
  }

  void _openApp(AppCard app) => openAppDetail(
    context,
    controller: _ctrl,
    alias: app.alias,
    family: _ctrl.familyOf(app),
    category: _ctrl.categoryFor(app),
  );

  @override
  void dispose() {
    _ctrl.removeListener(_onResults);
    _revealCurve.dispose();
    _reveal.dispose();
    _scroll.dispose();
    _searchCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: TickerMode.valuesOf(context).enabled
          ? _ctrl
          : Listenable.merge(const []),
      builder: (context, _) {
        _syncMode();
        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(child: _buildForMode(context)),
          floatingActionButton: CatalogFloatingActions(
            controller: _scroll,
            enabled: widget.active && _showsCatalog,
            onOpenBuilder: _ctrl.showsBuilder ? _openAssembler : null,
          ),
        );
      },
    );
  }

  bool get _showsCatalog =>
      AppsCatalogController.showsCatalog(_ctrl.mode.value);

  void _syncMode() {
    if (_ctrl.mode.value != CatalogMode.managerOnly) {
      _managerHandoff = false;
      return;
    }
    if (_managerHandoff) return;
    _managerHandoff = true;
    // A catalogue that could not be reached resolves to manager-only, which
    // on screen is indistinguishable from a firmware the catalogue does not
    // serve - so the user was told their Flipper was the problem when the
    // network was. The flag has existed all along and only Settings -> Apps
    // read it. #112.
    final offline = AppsBackend.instance.catalogOffline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (offline && mounted) {
        context.showNotification(
          context.l10n.appsCatalogUnreachable,
          type: QNotificationType.warning,
        );
      }
      widget.onOpenManager?.call();
    });
  }

  Widget _buildForMode(BuildContext context) {
    if (_showsCatalog) return _buildCatalog(context);
    if (_ctrl.mode.value == CatalogMode.resolving) {
      return Center(
        child: CircularProgressIndicator(color: context.appColors.accent),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCatalog(BuildContext context) {
    final gutter = catalogGutter(context);
    // Back and Escape leave the search before they leave the page.
    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_searchOpen) _closeSearch();
          },
        },
        child: _buildScroll(context, gutter),
      ),
    );
  }

  Widget _buildScroll(BuildContext context, double gutter) {
    final colors = context.appColors;
    return RefreshIndicator(
      color: colors.accent,
      edgeOffset: _headerHeight(context),
      // This one already returned its work; what it did not have is a
      // handler. `RefreshIndicator` does not catch a rejected `onRefresh`, so
      // a failed category load reached the zone as `[uncaught]`. #23
      onRefresh: () => guarded('[AppsCatalog] pull to refresh', () async {
        await _ctrl.loadCategories();
        await _ctrl.refresh();
      }),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(context, gutter),
          if (_searchOpen)
            SliverToBoxAdapter(child: _buildSearchField(context, gutter)),
          SliverToBoxAdapter(child: _buildFilters(context, gutter)),
          ..._revealed(_buildResults(context)),
          SliverToBoxAdapter(
            child: CatalogFooter(
              controller: _ctrl,
              hasItems: switch (_ctrl.searchView) {
                null => _ctrl.apps.isNotEmpty,
                CatalogSearchView.authors => _ctrl.authors.isNotEmpty,
                CatalogSearchView.everything => false,
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Results only fade in once there are some; spinners and empty states
  /// fill the remaining space and stay outside the group.
  List<Widget> _revealed(List<Widget> slivers) {
    if (!_hasResults) return slivers;
    return [
      SliverFadeTransition(
        opacity: _revealCurve,
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
    ];
  }

  /// Below this width the header keeps two rows; above it, one.
  static const double _compactWidth = 600;

  /// The official catalog (v0) has the apps only: one section, no tabs.
  /// Everything else on the page is the same for both protocols.
  bool get _hasSections => _ctrl.api.hasV1;

  /// Title and actions in a row of their own: on a phone, where the tabs
  /// need the full width, and wherever there are no tabs to take its place.
  bool _titleRow(BuildContext context) =>
      !_hasSections || MediaQuery.sizeOf(context).width < _compactWidth;

  /// Height of the pinned header, for the pull-to-refresh indicator.
  double _headerHeight(BuildContext context) => !_titleRow(context)
      ? _toolbarHeight
      : _compactToolbarHeight + (_hasSections ? 48 : 0);

  /// The pinned header. Wide: one row, the sections as tabs where the page
  /// title would be and the actions at its end. On a phone that row leaves
  /// the tabs no room, so it stays the familiar two: title and actions, then
  /// the tabs across the full width.
  Widget _buildAppBar(BuildContext context, double gutter) {
    final colors = context.appColors;
    final compact = _titleRow(context);
    final tabs = CatalogTabs(
      family: _ctrl.family,
      view: _ctrl.searchView,
      padding: gutter,
      onSelect: _select,
      trailing: compact
          ? null
          : Padding(
              padding: EdgeInsets.only(right: gutter - 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildActions(context),
              ),
            ),
    );
    return SliverAppBar(
      pinned: true,
      primary: false,
      automaticallyImplyLeading: false,
      toolbarHeight: compact ? _compactToolbarHeight : _toolbarHeight,
      titleSpacing: compact ? gutter : 0,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.scrolledUnder)
            ? colors.card
            : colors.background,
      ),
      foregroundColor: colors.textPrimary,
      title: compact ? _buildTitle(context) : tabs,
      actions: compact
          ? [..._buildActions(context), SizedBox(width: gutter - 8)]
          : null,
      bottom: compact && _hasSections ? tabs : null,
    );
  }

  Widget _modeBadge() => CatalogModeBadge(
    mode: _ctrl.mode.value,
    deviceApi: _ctrl.deviceApi,
    catalogApi: _ctrl.compatApi ?? _ctrl.serverApi,
  );

  Widget _buildTitle(BuildContext context) {
    final colors = context.appColors;
    return Text(
      context.l10n.appsStatusCatalog,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
    );
  }

  /// Order, search, manager, submit - every one in sight. The order is an
  /// icon like the others, with a dot once it is not the default.
  List<Widget> _buildActions(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    return [
      // First of the actions in every layout, so it never changes sides.
      _modeBadge(),
      if (_ctrl.searchView == null)
        CatalogSortButton(
          value: _ctrl.sort,
          onChanged: _selectSort,
          compact: true,
          v1: _ctrl.api.hasV1,
        ),
      IconButton(
        tooltip: _searchOpen
            ? s.commonClose
            : MaterialLocalizations.of(context).searchFieldLabel,
        icon: Icon(
          _searchOpen ? Icons.close : Icons.search,
          color: colors.textPrimary,
        ),
        onPressed: _searchOpen ? _closeSearch : _openSearch,
      ),
      _buildMenu(context),
    ];
  }

  /// What is used least goes behind the overflow button, the same in every
  /// layout: the apps on the device, how to publish, the apps settings.
  Widget _buildMenu(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    Widget item(IconData icon, String label, VoidCallback onPressed) =>
        MenuItemButton(
          leadingIcon: Icon(icon, size: 20, color: colors.textSecondary),
          onPressed: onPressed,
          child: Text(label, style: TextStyle(color: colors.textPrimary)),
        );
    return MenuAnchor(
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
        item(
          Icons.inventory_2_outlined,
          s.catalogManageTooltip,
          () => widget.onOpenManager?.call(),
        ),
        item(
          Icons.add_circle_outline,
          s.catalogSubmitTooltip,
          () => SubmitAppDialog.show(context),
        ),
        item(
          Icons.settings_outlined,
          s.settingsTitle,
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AppsSettingsPage())),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        icon: Icon(Icons.more_vert, color: colors.textPrimary),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, double gutter) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: _ctrl.setQuery,
        decoration: InputDecoration(
          hintText: context.l10n.catalogSearchHint,
          prefixIcon: Icon(Icons.search, color: colors.textMuted),
          filled: true,
          fillColor: colors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 0,
          ),
        ),
      ),
    );
  }

  /// Category chips stay exactly as designed; the order control lives in
  /// the tab row above.
  Widget _buildFilters(BuildContext context, double gutter) {
    if (_ctrl.searchView != null) return const SizedBox(height: 12);
    return Padding(
      // Clear of the header's divider and the tab indicator above it.
      padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 16),
      child: AnimatedSize(
        duration: _reduceMotion ? Duration.zero : Durations.medium2,
        curve: Easing.emphasizedDecelerate,
        alignment: Alignment.topLeft,
        child: CategoriesFilter(
          categories: _ctrl.categories,
          current: _ctrl.currentCategory,
          onSelect: _selectCategory,
          allLabel: switch (_ctrl.family) {
            CatalogFamily.apps => null,
            CatalogFamily.animations => context.l10n.catalogAllAnimations,
            CatalogFamily.menuStyles => context.l10n.catalogAllMenuStyles,
            CatalogFamily.cli => context.l10n.catalogAllCli,
          },
        ),
      ),
    );
  }

  String? _needsV1Message(BuildContext context) {
    final error = _ctrl.lastError;
    if (error is! CatalogNeedsV1Exception) return null;
    if (error.search) return context.l10n.catalogSearchUnsupported;
    return switch (error.family) {
      null || CatalogFamily.apps => context.l10n.appsSortUnsupported,
      CatalogFamily.animations => context.l10n.appsFamilyUnsupported,
      CatalogFamily.menuStyles => context.l10n.appsMenuStylesUnsupported,
      CatalogFamily.cli => context.l10n.appsCliUnsupported,
    };
  }

  Widget _spinner(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: CircularProgressIndicator(color: context.appColors.accent),
    ),
  );

  Widget _placeholder(BuildContext context, {String? emptyMessage}) {
    if (_ctrl.appsLoading) return _spinner(context);
    final failed = _ctrl.lastError != null;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: CatalogEmptyView(
        failed: failed,
        message: _needsV1Message(context) ?? (failed ? null : emptyMessage),
      ),
    );
  }

  List<Widget> _buildResults(BuildContext context) {
    switch (_ctrl.searchView) {
      case null:
        if (_ctrl.categoriesLoading && _ctrl.categories.isEmpty) {
          return [_spinner(context)];
        }
        return [
          CatalogGrid(
            controller: _ctrl,
            apps: _ctrl.apps,
            family: _ctrl.family,
            onOpen: _openApp,
            emptyMessage: _needsV1Message(context),
          ),
        ];
      case CatalogSearchView.authors:
        final authors = _ctrl.authors;
        if (authors.isEmpty) {
          return [
            _placeholder(context, emptyMessage: context.l10n.catalogNoAuthors),
          ];
        }
        return [AuthorsGrid(authors: authors, onOpen: _openAuthor)];
      case CatalogSearchView.everything:
        final result = _ctrl.searchResult;
        if (result == null) return [_placeholder(context)];
        return _buildEverything(context, result);
    }
  }

  List<Widget> _buildEverything(BuildContext context, CatalogSearch result) {
    final sections = <Widget>[];
    if (result.authors.isNotEmpty) {
      sections
        ..add(
          _sectionHeader(
            context,
            context.l10n.catalogScopeAuthors,
            result.authors.length,
            () => _ctrl.selectSearchView(CatalogSearchView.authors),
          ),
        )
        ..add(
          SliverToBoxAdapter(
            child: AuthorsStrip(
              authors: result.authors,
              onOpen: _openAuthor,
              padding: EdgeInsets.symmetric(horizontal: catalogGutter(context)),
            ),
          ),
        );
    }
    for (final family in CatalogFamily.values) {
      final items = result.itemsOf(family);
      if (items.isEmpty) continue;
      sections
        ..add(
          _sectionHeader(
            context,
            catalogFamilyLabel(context, family),
            result.totals[family],
            () => guarded(
              '[AppsCatalog] show all search results',
              () => _ctrl.selectFamily(family),
            ),
          ),
        )
        ..add(
          CatalogGrid(
            controller: _ctrl,
            apps: items,
            family: family,
            onOpen: _openApp,
          ),
        );
    }
    if (sections.isEmpty) return [_placeholder(context)];
    return sections;
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    int? count,
    VoidCallback onShowAll,
  ) {
    final colors = context.appColors;
    final gutter = catalogGutter(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 16, gutter - 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                count == null ? title : '$title · $count',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: onShowAll,
              child: Text(
                context.l10n.catalogShowAll,
                style: TextStyle(color: colors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAuthor(AuthorSummary author) =>
      openAuthorPage(context, author.author);
}
