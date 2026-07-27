import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/open_url.dart';
import '../../tools/remote/desktop/page.dart';
import 'detail_page.dart';
import 'controller.dart';
import '../manager/page.dart';
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

class _AppsCatalogPageState extends State<AppsCatalogPage> {
  final AppsCatalogController _ctrl = AppsCatalogController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _ctrl.compatibilityNeeded.addListener(_onCompatNeeded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.initialize();
    });
  }

  bool _compatDialogOpen = false;

  void _onCompatNeeded() {
    if (!mounted || _compatDialogOpen || _ctrl.apiFallbackEnabled) {
      return;
    }
    _compatDialogOpen = true;
    final device = _ctrl.deviceApi ?? '?';
    final fallback = _ctrl.fallbackApi ?? 'an older SDK';
    showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.appColors;
        return AlertDialog(
          backgroundColor: colors.dialogBackground,
          title: Text('Enable compatibility mode?',
              style: TextStyle(color: colors.dialogText)),
          content: Text(
            'Your firmware is API $device, but the catalog only has builds for '
            'API $fallback. Compatibility mode installs those older builds '
            'anyway.\n\nThey may fail to launch or misbehave on newer firmware.',
            style: TextStyle(color: colors.dialogText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Not now', style: TextStyle(color: colors.dialogMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Enable', style: TextStyle(color: colors.accent)),
            ),
          ],
        );
      },
    ).then((ok) {
      _compatDialogOpen = false;
      if (ok == true) _ctrl.enableCompatibility();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _ctrl.loadMore();
    }
  }

  void _onLaunched() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteControlPage()));
  }

  void _openApp(AppCard app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppDetailPage(
          alias: app.alias,
          controller: _ctrl,
          knownCategory: _ctrl.categoryById(app.categoryId),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.compatibilityNeeded.removeListener(_onCompatNeeded);
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
              if (_ctrl.apiFallbackEnabled) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Compatibility mode: installing older builds (API ${_ctrl.fallbackApi ?? '?'})',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 13, color: colors.accent),
                        const SizedBox(width: 4),
                        Text('Compat',
                            style: TextStyle(
                                color: colors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                icon: Icon(Icons.smartphone, color: colors.textPrimary),
                tooltip: 'Manage apps on device',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppsManagerPage()),
                ),
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apps, size: 48, color: colors.textMuted),
              const SizedBox(height: 8),
              Text(
                _ctrl.lastError != null
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
          final cross =
              (constraints.crossAxisExtent / cardWidth).floor().clamp(1, 6);
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
