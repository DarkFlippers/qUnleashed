import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/dialogs/catalog_compat.dart';
import '../../../components/icon.dart';
import '../../../components/dialogs/catalog_states.dart';
import '../../../theme/theme.dart';
import '../../../widgets/open_url.dart';
import '../../asembler/controller.dart';
import '../../asembler/page.dart';
import '../../tools/remote/desktop/page.dart';
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

class _AppsCatalogPageState extends State<AppsCatalogPage> {
  bool _manager = false;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _manager ? 1 : 0,
      children: [
        CatalogView(
          active: !_manager,
          onOpenManager: () => setState(() => _manager = true),
        ),
        AppsManagerPage(onOpenCatalog: () => setState(() => _manager = false)),
      ],
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
  bool _incompatKnown = false;

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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssemblerConsolePage()));
  }

  void _chooseSourceBuild() => _ctrl.chooseSourceBuild();

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
          floatingActionButton: _showsCatalog && AssemblerController.isSupported
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

  bool get _showsCatalog =>
      _ctrl.mode.value == CatalogMode.normal ||
      _ctrl.mode.value == CatalogMode.compatibility;

  void _syncMode() {
    final mode = _ctrl.mode.value;
    if (mode != CatalogMode.incompatible ||
        _ctrl.incompatibility == ApiVerdict.tooNew) {
      _incompatKnown = false;
      return;
    }
    if (_incompatKnown) return;
    _incompatKnown = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onOpenManager?.call(),
    );
  }

  Widget _buildForMode(BuildContext context) {
    switch (_ctrl.mode.value) {
      case CatalogMode.resolving:
        return const SizedBox.shrink();
      case CatalogMode.mismatch:
        return _dialogLayer(
          CatalogCompatDialog(
            deviceApi: _ctrl.deviceApi,
            serverApi: _ctrl.serverApi,
            onBuildFromSource: AssemblerController.isSupported
                ? _chooseSourceBuild
                : null,
            onIgnoreAndContinue: _ctrl.chooseCompatibility,
            onDecline: () => widget.onOpenManager?.call(),
          ),
        );
      case CatalogMode.incompatible:
        if (_ctrl.incompatibility == ApiVerdict.tooNew) {
          return _dialogLayer(
            CatalogCompatDialog(
              deviceApi: _ctrl.deviceApi,
              serverApi: _ctrl.serverApi,
              onBuildFromSource: AssemblerController.isSupported
                  ? _chooseSourceBuild
                  : null,
              onIgnoreAndContinue: null,
              onDecline: () => widget.onOpenManager?.call(),
            ),
          );
        }
        return _dialogLayer(
          CatalogIncompatibleDialog(
            deviceApi: _ctrl.deviceApi,
            serverApi: _ctrl.serverApi,
            onOpenManager: () => widget.onOpenManager?.call(),
            onRecheck: () => unawaited(_ctrl.refreshMode()),
          ),
        );
      case CatalogMode.normal:
      case CatalogMode.compatibility:
        return _buildCatalog(context);
    }
  }

  Widget _dialogLayer(Widget dialog) {
    return ColoredBox(
      color: context.appColors.dialogBarrier,
      child: Center(child: SingleChildScrollView(child: dialog)),
    );
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
              if (_ctrl.apiFallbackEnabled) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Compatibility mode: installing builds for API ${_ctrl.compatApi ?? '?'}',
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: colors.accent,
                    ),
                  ),
                ),
              ],
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
