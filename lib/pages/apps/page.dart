import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/theme.dart';
import '../../widgets/open_url.dart';
import '../tools/remote/desktop/page.dart';
import 'detail_page.dart';
import 'controller.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'widgets/action_button.dart';
import 'widgets/card.dart';
import 'widgets/categories_filter.dart';
import 'widgets/flipper_image.dart';
import 'widgets/sort_dropdown.dart';

const String _kContributingUrl =
    'https://github.com/flipperdevices/flipper-application-catalog/blob/main/documentation/Contributing.md';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  final AppsCatalogController _ctrl = AppsCatalogController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _ctrl.initialize();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _ctrl.loadMore();
    }
  }

  void _cycleFilter() {
    final next = switch (_ctrl.filter) {
      AppsCatalogFilter.all => AppsCatalogFilter.installed,
      AppsCatalogFilter.installed => AppsCatalogFilter.updates,
      AppsCatalogFilter.updates => AppsCatalogFilter.all,
    };
    _ctrl.setFilter(next);
  }

  void _onLaunched() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteControlPage()));
  }

  AppCategory? _scanningCategory() {
    final name = _ctrl.install.scanningCategoryName?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    for (final cat in _ctrl.categories) {
      if (cat.name.trim().toLowerCase() == name) return cat;
    }
    return null;
  }

  void _openApp(AppCard app) {
    final cat = _ctrl.categoryById(app.categoryId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppDetailPage(
          alias: app.alias,
          api: _ctrl.api,
          installService: _ctrl.install,
          knownCategory: cat,
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
        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: RefreshIndicator(
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
            ),
          ),
        );
      },
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
              const Spacer(),
              if (_ctrl.filter == AppsCatalogFilter.updates)
                _UpdateAllButton(
                  enabled:
                      _ctrl.install.isReady && _ctrl.updatableApps.isNotEmpty,
                  onTap: _ctrl.updateAll,
                )
              else if (_ctrl.install.isReady)
                _ScanIconButton(
                  scanning: _ctrl.install.scanning,
                  category: _scanningCategory(),
                  onTap: () => _ctrl.install.rescanInstalled(),
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
          Row(
            children: [
              SortDropdown(value: _ctrl.sort, onChanged: _ctrl.selectSort),
              const SizedBox(width: 8),
              _FilterChip(
                filter: _ctrl.filter,
                updatesCount: _ctrl.updatableApps.length,
                onTap: _cycleFilter,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAppsGrid(BuildContext context) {
    final colors = context.appColors;
    final apps = _ctrl.displayedApps;

    if (apps.isEmpty) {
      if (_ctrl.viewLoading) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: colors.accent)),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apps, size: 48, color: colors.textMuted),
              const SizedBox(height: 8),
              Text(
                _ctrl.viewError != null
                    ? 'Failed to load apps'
                    : 'No apps found',
                style: TextStyle(color: colors.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
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
              final cat = _ctrl.categoryById(app.categoryId);
              return AppCardView(
                app: app,
                category: cat,
                onTap: () => _openApp(app),
                action: AppActionButton(
                  service: _ctrl.install,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.updatesCount,
    required this.onTap,
  });

  final AppsCatalogFilter filter;
  final int updatesCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = filter != AppsCatalogFilter.all;
    final background = switch (filter) {
      AppsCatalogFilter.all => colors.card,
      AppsCatalogFilter.installed => colors.accent,
      AppsCatalogFilter.updates => colors.success,
    };
    final foreground = active ? colors.onAccent : colors.textMuted;
    final label = switch (filter) {
      AppsCatalogFilter.all || AppsCatalogFilter.installed => 'Installed',
      AppsCatalogFilter.updates =>
        updatesCount > 0 ? 'Updates ($updatesCount)' : 'Updates',
    };
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/ic/state/installed.svg',
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateAllButton extends StatelessWidget {
  const _UpdateAllButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      tooltip: 'Update all',
      onPressed: enabled ? onTap : null,
      icon: Icon(
        Icons.system_update_alt,
        color: enabled ? colors.textPrimary : colors.textMuted,
      ),
    );
  }
}

class _ScanIconButton extends StatelessWidget {
  const _ScanIconButton({
    required this.scanning,
    required this.onTap,
    this.category,
  });

  final bool scanning;
  final AppCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconUri = category?.iconUri;
    return Tooltip(
      message: scanning && category != null
          ? 'Scanning ${category!.name}…'
          : 'Scan device for all apps',
      child: IconButton(
        onPressed: scanning ? null : onTap,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: scanning
              ? SizedBox(
                  key: const ValueKey('scan-loading'),
                  width: 20,
                  height: 20,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.textPrimary,
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: iconUri != null && iconUri.isNotEmpty
                            ? SafeNetworkSvg(
                                key: ValueKey('scan-cat-${category!.id}'),
                                url: iconUri,
                                width: 10,
                                height: 10,
                                colorFilter: ColorFilter.mode(
                                  colors.textPrimary,
                                  BlendMode.srcIn,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('scan-cat-none'),
                              ),
                      ),
                    ],
                  ),
                )
              : Icon(
                  key: const ValueKey('scan-icon'),
                  Icons.manage_search,
                  color: colors.textPrimary,
                ),
        ),
      ),
    );
  }
}
