import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/open_url.dart';
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
        CatalogView(onOpenManager: () => setState(() => _manager = true)),
        AppsManagerPage(onOpenCatalog: () => setState(() => _manager = false)),
      ],
    );
  }
}

class CatalogView extends StatefulWidget {
  const CatalogView({super.key, this.onOpenManager});

  final VoidCallback? onOpenManager;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final AppsCatalogController _ctrl = AppsCatalogController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  bool _compatDialogOpen = false;

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
        _maybeShowCompatDialog();
        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(child: _buildForMode(context)),
        );
      },
    );
  }

  void _maybeShowCompatDialog() {
    if (_compatDialogOpen) return;
    if (_ctrl.mode.value != CatalogMode.mismatch) return;
    _compatDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showCompatDialog());
  }

  Future<void> _showCompatDialog() async {
    if (!mounted || _ctrl.mode.value != CatalogMode.mismatch) {
      _compatDialogOpen = false;
      return;
    }
    final choice = await showDialog<_CompatChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CompatDialog(
        deviceApi: _ctrl.deviceApi,
        serverApi: _ctrl.serverApi,
        compatApi: _ctrl.compatApi,
      ),
    );
    _compatDialogOpen = false;
    if (!mounted) return;
    if (choice == _CompatChoice.compat) {
      _ctrl.chooseCompatibility();
    } else if (choice == _CompatChoice.decline) {
      _ctrl.declineCatalog();
      widget.onOpenManager?.call();
    }
  }

  Widget _buildForMode(BuildContext context) {
    final colors = context.appColors;
    switch (_ctrl.mode.value) {
      case CatalogMode.resolving:
        return Center(child: CircularProgressIndicator(color: colors.accent));
      case CatalogMode.mismatch:
        return _MismatchPrompt(onChoose: _showCompatDialog);
      case CatalogMode.disabled:
        return _DisabledView(
          onOpenManager: widget.onOpenManager,
          onRecheck: _ctrl.refreshMode,
        );
      case CatalogMode.normal:
      case CatalogMode.compatibility:
        return _buildCatalog(context);
    }
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

enum _CompatChoice { compat, decline }

class _MismatchPrompt extends StatelessWidget {
  const _MismatchPrompt({required this.onChoose});

  final Future<void> Function() onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 56, color: Colors.amber.shade600),
            const SizedBox(height: 12),
            Text(
              'Compatibility check needed',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onChoose,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Choose an option'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompatDialog extends StatelessWidget {
  const _CompatDialog({
    required this.deviceApi,
    required this.serverApi,
    required this.compatApi,
  });

  final String? deviceApi;
  final String? serverApi;
  final String? compatApi;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 56, color: Colors.amber.shade600),
          const SizedBox(height: 12),
          Text(
            'Catalog / firmware mismatch',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.dialogText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ApiRow(
            label: 'Your firmware',
            value: deviceApi ?? '—',
            colors: colors,
          ),
          const SizedBox(height: 4),
          _ApiRow(label: 'Catalog', value: serverApi ?? '—', colors: colors),
          const SizedBox(height: 14),
          Text(
            'The catalog has no builds for your firmware API. Apps installed '
            'in compatibility mode may work incorrectly or fail to launch.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.dialogText, fontSize: 13),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_CompatChoice.compat),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  compatApi != null
                      ? 'Use compatibility mode (API $compatApi)'
                      : 'Use compatibility mode',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(_CompatChoice.decline),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.dialogMuted,
                  side: BorderSide(color: colors.dialogDivider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Not now - apps manager only'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ApiRow extends StatelessWidget {
  const _ApiRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label: ',
            style: TextStyle(color: colors.textMuted, fontSize: 13)),
        Text(
          'API $value',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DisabledView extends StatelessWidget {
  const _DisabledView({required this.onOpenManager, required this.onRecheck});

  final VoidCallback? onOpenManager;
  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 56, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Catalog disabled',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compatibility mode was declined. Only the apps manager is '
              'available for this firmware.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenManager,
              icon: const Icon(Icons.smartphone, size: 18),
              label: const Text('Open apps manager'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRecheck,
              child: Text('Re-check compatibility',
                  style: TextStyle(color: colors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
