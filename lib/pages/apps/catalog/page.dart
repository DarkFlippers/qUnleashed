import 'package:flutter/material.dart';

import '../../../components/icon.dart';
import 'widgets/mode_badge.dart';
import 'widgets/states.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import '../../../components/open_url.dart';
import '../../../services/assembler/controller.dart';
import '../data/apps_backend.dart';
import '../manager/install_page.dart';
import '../manager/page.dart';
import 'detail_page.dart';
import 'controller.dart';
import '../data/models/card.dart';
import 'widgets/card.dart';
import 'widgets/categories_filter.dart';
import 'widgets/action_button.dart';
import 'widgets/sort_dropdown.dart';

const String _kContributingUrl =
    'https://github.com/flipperdevices/flipper-application-catalog/blob/main/documentation/Contributing.md';

class AppsCatalogPage extends StatefulWidget {
  const AppsCatalogPage({super.key});

  @override
  State<AppsCatalogPage> createState() => _AppsCatalogPageState();
}

enum AppsView { catalog, manager, plugins }

class _AppsCatalogPageState extends State<AppsCatalogPage>
    with SingleTickerProviderStateMixin {
  AppsView _view = AppsView.catalog;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  void _show(AppsView view) {
    if (_view == view) return;
    setState(() => _view = view);
    _fade
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
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
                CatalogView(
                  active: _view == AppsView.catalog,
                  onOpenManager: () => _show(AppsView.manager),
                ),
                AppsManagerPage(
                  onOpenCatalog: hasCatalog
                      ? () => _show(AppsView.catalog)
                      : null,
                  onOpenPlugins: () => _show(AppsView.plugins),
                ),
                AtpInstallPage(
                  onOpenCatalog: hasCatalog
                      ? () => _show(AppsView.catalog)
                      : null,
                  onOpenManager: () => _show(AppsView.manager),
                ),
              ],
            ),
            IgnorePointer(
              child: FadeTransition(
                opacity: Tween<double>(
                  begin: 1,
                  end: 0,
                ).animate(CurvedAnimation(parent: _fade, curve: Curves.easeOut)),
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
  const CatalogView({super.key, this.onOpenManager, this.active = true});

  final VoidCallback? onOpenManager;
  final bool active;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final AppsCatalogController _ctrl = AppsCatalogController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  bool _managerHandoff = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.initialize();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _ctrl.loadMore();
    }
  }

  void _openAssembler() {
    openRoute(context, AppRoute.assemblerConsole);
  }

  void _onLaunched() {
    openRoute(context, AppRoute.remoteControl);
  }

  void _openApp(AppCard app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppDetailPage(
          alias: app.alias,
          controller: _ctrl,
          knownCategory: _ctrl.categoryFor(app),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        _syncMode();
        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(child: _buildForMode(context)),
          floatingActionButton: _showsBuilder
              ? FloatingActionButton(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  tooltip: 'Assembler',
                  onPressed: _openAssembler,
                  child: QIcon(
                    asset: 'assets/ic/fileformat/settings.svg',
                    color: colors.onAccent,
                    size: 24,
                  ),
                )
              : null,
        );
      },
    );
  }

  bool get _showsCatalog => AppsCatalogController.showsCatalog(_ctrl.mode.value);

  /// The assembler console only has something to show while the catalog builds
  /// apps from source, so the button follows the mode, not the platform alone.
  bool get _showsBuilder =>
      _ctrl.mode.value == CatalogMode.sourceBuild &&
      AssemblerController.isSupported;

  void _syncMode() {
    if (_ctrl.mode.value != CatalogMode.managerOnly) {
      _managerHandoff = false;
      return;
    }
    if (_managerHandoff) return;
    _managerHandoff = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onOpenManager?.call(),
    );
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
    final colors = context.appColors;
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () async {
        await _ctrl.loadCategories();
        await _ctrl.refresh();
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context)),
          if (_ctrl.categoriesLoading && _ctrl.categories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: colors.accent),
              ),
            )
          else
            _buildAppsGrid(context),
          SliverToBoxAdapter(child: _buildFooter(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Apps catalog',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              CatalogModeBadge(
                mode: _ctrl.mode.value,
                deviceApi: _ctrl.deviceApi,
                catalogApi: _ctrl.compatApi ?? _ctrl.serverApi,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.manage_search, color: colors.textPrimary),
                tooltip: 'Manage apps on device',
                onPressed: widget.onOpenManager,
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: colors.textPrimary),
                tooltip: 'How to submit your app',
                onPressed: () => openUrl(context, _kContributingUrl),
              ),
              IconButton(
                icon: Icon(
                  _searchOpen ? Icons.close : Icons.search,
                  color: colors.textPrimary,
                ),
                onPressed: () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _searchCtrl.clear();
                      _ctrl.setQuery('');
                    }
                  });
                },
              ),
            ],
          ),
          if (_searchOpen) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _ctrl.setQuery,
              decoration: InputDecoration(
                hintText: 'Search apps',
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
          ],
          const SizedBox(height: 12),
          CategoriesFilter(
            categories: _ctrl.categories,
            current: _ctrl.currentCategory,
            onSelect: _ctrl.selectCategory,
          ),
          const SizedBox(height: 12),
          SortDropdown(value: _ctrl.sort, onChanged: _ctrl.selectSort),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAppsGrid(BuildContext context) {
    final colors = context.appColors;
    final apps = _ctrl.apps;

    if (apps.isEmpty) {
      if (_ctrl.appsLoading) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: colors.accent)),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: CatalogEmptyView(failed: _ctrl.lastError != null),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const cardWidth = 360.0;
          final cross = (constraints.crossAxisExtent / cardWidth).floor().clamp(
            1,
            6,
          );
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 220,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final app = apps[index];
              final cat = _ctrl.categoryFor(app);
              return AppCardView(
                app: app,
                category: cat,
                onTap: () => _openApp(app),
                action: AppActionButton(
                  engine: _ctrl.engine,
                  state: _ctrl.stateFor(app),
                  app: app,
                  category: cat,
                  onLaunched: _onLaunched,
                ),
              );
            }, childCount: apps.length),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = context.appColors;
    if (_ctrl.appsLoading && _ctrl.apps.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }
    if (_ctrl.reachedEnd && _ctrl.apps.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '— End of catalog —',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}
