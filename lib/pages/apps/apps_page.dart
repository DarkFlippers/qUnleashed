import 'package:flutter/material.dart';

import '../../theme.dart';
import '../devices/remote_control_page.dart';
import 'app_detail_page.dart';
import 'apps_controller.dart';
import 'models/app_card.dart';
import 'widgets/app_action_button.dart';
import 'widgets/app_card.dart';
import 'widgets/categories_filter.dart';
import 'widgets/sort_dropdown.dart';

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
    _ctrl.install.ensureScanned();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _ctrl.loadMore();
    }
  }

  void _onLaunched() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
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
                'Apps',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(_searchOpen ? Icons.close : Icons.search, color: colors.textPrimary),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
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
          Align(
            alignment: Alignment.centerLeft,
            child: SortDropdown(value: _ctrl.sort, onChanged: _ctrl.selectSort),
          ),
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apps, size: 48, color: colors.textMuted),
              const SizedBox(height: 8),
              Text(
                _ctrl.lastError != null ? 'Failed to load apps' : 'No apps found',
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
          final cross = (constraints.crossAxisExtent / cardWidth).floor().clamp(1, 6);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 220,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
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
              },
              childCount: apps.length,
            ),
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
