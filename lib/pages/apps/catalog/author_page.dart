import 'package:flutter/material.dart';

import 'package:qunleashed/components/appbar.dart';

import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../../devices/device_scope.dart';
import '../data/apps_backend.dart';
import '../data/catalog_api.dart' show CatalogFamily;
import '../data/models/author.dart';
import 'controller.dart';
import 'detail_page.dart';
import 'routes.dart';
import 'widgets/author_card.dart';
import 'widgets/card.dart';
import 'widgets/catalog_grid.dart';
import 'widgets/category_chip.dart';
import 'widgets/sort_button.dart';
import 'widgets/states.dart';
import 'widgets/floating_actions.dart';

void openAuthorPage(BuildContext context, AppAuthor author) {
  openCatalogRoute(
    context,
    catalogAuthorPath(author.id),
    (_) => AuthorPage(author: author),
  );
}

class AuthorPage extends StatefulWidget {
  const AuthorPage({super.key, required this.author});

  final AppAuthor author;

  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  final ScrollController _scroll = ScrollController();

  AuthorSummary? _summary;
  AppsCatalogController? _ctrl;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    guarded('[AppsCatalog] load author', _load);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final summary = await AppsBackend.instance.api.fetchAuthor(
        widget.author.id,
      );
      if (!mounted) return;
      final ctrl = AppsCatalogController(
        authorId: summary.id,
        family: _familiesOf(summary).firstOrNull ?? CatalogFamily.apps,
      );
      setState(() {
        _summary = summary;
        _ctrl = ctrl;
      });
      await ctrl.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  static List<CatalogFamily> _familiesOf(AuthorSummary summary) => [
    for (final family in CatalogFamily.values)
      if ((summary.counts[family.serverName] ?? 0) > 0) family,
  ];

  void _onScroll() {
    final ctrl = _ctrl;
    if (ctrl == null || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) ctrl.loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        client: DeviceScope.clientOf(context),
        title: context.l10n.authorPageTitle,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
      ),
      body: _buildBody(context),
      floatingActionButton: CatalogFloatingActions(controller: _scroll),
    );
  }

  Widget _buildBody(BuildContext context) {
    final summary = _summary;
    final ctrl = _ctrl;
    if (_error != null) {
      return AppDetailErrorView(
        message: context.l10n.authorLoadFailed,
        onRetry: () => guarded('[AppsCatalog] load author', _load),
      );
    }
    if (summary == null || ctrl == null) {
      return Center(
        child: CircularProgressIndicator(color: context.appColors.accent),
      );
    }
    return AnimatedBuilder(
      animation: TickerMode.valuesOf(context).enabled
          ? ctrl
          : Listenable.merge(const []),
      builder: (context, _) => CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, summary, ctrl)),
          CatalogGrid(
            controller: ctrl,
            apps: ctrl.apps,
            family: ctrl.family,
            onOpen: (app) => openAppDetail(
              context,
              controller: ctrl,
              alias: app.alias,
              family: ctrl.familyOf(app),
              category: ctrl.categoryFor(app),
            ),
          ),
          SliverToBoxAdapter(
            child: CatalogFooter(
              controller: ctrl,
              hasItems: ctrl.apps.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AuthorSummary summary,
    AppsCatalogController ctrl,
  ) {
    final colors = context.appColors;
    final families = _familiesOf(summary);
    final downloads = summary.downloads;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              return Row(
                children: [
                  AuthorAvatar(name: summary.name, size: compact ? 52 : 64),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${summary.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              context.l10n.authorWorks(summary.total),
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            if ((downloads ?? 0) > 0) ...[
                              const SizedBox(width: 10),
                              DownloadsBadge(count: downloads!, fontSize: 13),
                            ],
                          ],
                        ),
                        if (families.length > 1) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final family in families)
                                FamilyChip(
                                  family: family,
                                  count: summary.counts[family.serverName],
                                  selected: ctrl.family == family,
                                  onTap: () => guarded(
                                    '[AppsCatalog] select author section',
                                    () => ctrl.selectFamily(family),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CatalogSortButton(
                    value: ctrl.sort,
                    onChanged: ctrl.selectSort,
                    compact: compact,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: colors.divider),
        ],
      ),
    );
  }
}
