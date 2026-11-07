import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../actions.dart';
import 'widgets/states.dart';
import 'widgets/animation_preview.dart';
import 'widgets/author_card.dart';
import '../../../theme/theme.dart';

import 'package:qunleashed/components/appbar.dart';

import '../../../components/open_url.dart';
import '../data/models/author.dart';
import '../data/models/category.dart';
import '../data/models/detail.dart';
import '../data/models/app_entry.dart';
import '../data/catalog_api.dart' show CatalogFamily;
import 'author_page.dart';
import 'controller.dart';
import 'routes.dart';
import '../../../services/logging.dart';
import 'widgets/action_button.dart';
import 'widgets/card.dart';
import 'widgets/category_chip.dart';
import 'widgets/app_picker.dart';
import 'widgets/detail_sections.dart';
import '../../devices/device_scope.dart';

void openAppDetail(
  BuildContext context, {
  required AppsCatalogController controller,
  required String alias,
  required CatalogFamily family,
  AppCategory? category,
}) {
  openCatalogRoute(
    context,
    catalogAppPath(family, alias),
    (_) => AppDetailPage(
      alias: alias,
      controller: controller,
      family: family,
      knownCategory: category,
    ),
  );
}

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({
    super.key,
    required this.alias,
    required this.controller,
    required this.family,
    this.knownCategory,
  });

  final String alias;
  final AppsCatalogController controller;
  final CatalogFamily family;
  final AppCategory? knownCategory;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  AppsCatalogController get _ctrl => widget.controller;

  /// The item as the server sent it, its default entry in front.
  AppDetail? _detail;

  /// What the page shows: [_detail] as the picked entry.
  AppDetail? _view;
  CatalogApp? _selectedApp;

  List<AuthorSummary> _authors = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _ctrl.api.fetchApp(widget.alias, family: widget.family);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _view = d;
        _selectedApp = _leading(d);
        _authors = [
          for (final author in d.card.authors)
            AuthorSummary(author: author, counts: const {}),
        ];
        _loading = false;
      });
      await _loadAuthors(d.card.authors);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static CatalogApp? _leading(AppDetail detail) {
    final entries = detail.card.entries;
    for (final entry in entries) {
      if (entry.id == detail.card.selectedAppId) return entry;
    }
    return entries.isEmpty ? null : entries.first;
  }

  void _pick(CatalogApp entry) {
    final detail = _detail;
    if (detail == null) return;
    setState(() {
      _selectedApp = entry;
      _view = detail.forApp(entry);
    });
  }

  Future<void> _loadAuthors(List<AppAuthor> authors) async {
    if (!_ctrl.api.hasV1) return;
    final failed = <String>[];
    Object? last;
    for (var i = 0; i < authors.length; i++) {
      try {
        final summary = await _ctrl.api.fetchAuthor(authors[i].id);
        if (!mounted) return;
        setState(() => _authors = [..._authors]..[i] = summary);
      } catch (e) {
        failed.add(authors[i].id);
        last = e;
      }
    }
    // One line per page: the cards stay as the listing drew them.
    if (failed.isNotEmpty) {
      LogService.caught('[AppDetail] authors ${failed.join(', ')}: $last');
    }
  }

  /// Neither the device scope nor the catalog controller is listened to from
  /// here.
  ///
  /// The body carries up to three `SelectionArea`s over `flutter_html`, and a
  /// rebuild throws away a live text selection in them. A selection handle
  /// dragged across that rebuild then crashes inside a gesture callback, where
  /// nothing on this page can catch it. Neither ticker reaches the body: the
  /// catalog controller stops at [_DetailAppBar], the install button and the
  /// entry picker,
  /// and the device-info poll no longer rebuilds anything this page builds at
  /// all, now that the bar reads `DeviceScope.clientOf` and depends on
  /// nothing. `test/app_detail_rebuild_scope_test.dart` holds the mechanism
  /// and both notification rates. QUNLEASHED-F, #344.
  ///
  /// The poll is not *absent* from the subtree - `QPageAppBar`'s title widget
  /// takes its own `deviceInfoUpdates` subscription and `setState`s on each
  /// patch (`components/appbar.dart`), which is how the subtitle tracks the
  /// device. That rebuild stops inside the bar, and is the reason the bar
  /// never wanted the scope's notification in the first place.
  ///
  /// A theme or locale change still rebuilds the body - `context.appColors`
  /// below is an inherited dependency, and `lib/app/app.dart` rebuilds the
  /// `MaterialApp` on both - and so does a reload through `_load`. Neither is
  /// on a timer, and neither is this page's to decide.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: _DetailAppBar(
        controller: _ctrl,
        detail: _view,
        family: widget.family,
        knownCategory: widget.knownCategory,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null || _view == null) {
      return AppDetailErrorView(onRetry: _load);
    }

    final detail = _view!;
    final card = detail.card;
    final cv = card.currentVersion;
    final entry = _selectedApp;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Header(
          detail: detail,
          controller: _ctrl,
          family: widget.family,
          knownCategory: widget.knownCategory,
          // Listens for itself: which entry is installed is the controller's.
          picker: entry != null && card.entries.length > 1
              ? AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => CatalogAppPicker(
                    entries: card.entries,
                    selected: entry,
                    onChanged: _pick,
                    isInstalled: (v) =>
                        _ctrl.engine.isInstalled(_detail!.card.forApp(v)),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 18),
        if (cv != null && widget.family == CatalogFamily.animations) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: AnimationPreview(
                files: _ctrl.animationFiles,
                versionId: cv.id,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ] else if (cv != null && cv.screenshots.isNotEmpty) ...[
          DetailScreenshotsRow(screenshots: cv.screenshots, title: card.name),
          const SizedBox(height: 18),
        ],
        if (_authors.isNotEmpty) ...[
          DetailSectionTitle(title: context.l10n.catalogScopeAuthors),
          const SizedBox(height: 8),
          AuthorsStrip(
            authors: _authors,
            onOpen: (author) => openAuthorPage(context, author.author),
          ),
          const SizedBox(height: 18),
        ],

        if (cv != null && cv.shortDescription.isNotEmpty) ...[
          DetailSectionTitle(title: context.l10n.appSectionDescription),
          const SizedBox(height: 6),
          DetailMarkdown(source: cv.shortDescription),
        ],
        if (detail.description.isNotEmpty) ...[
          DetailMarkdown(source: detail.description),
          const SizedBox(height: 12),
        ],
        if (detail.changelog.isNotEmpty) ...[
          DetailSectionTitle(title: context.l10n.appSectionChangelog),
          const SizedBox(height: 6),
          DetailMarkdown(source: detail.changelog),
          const SizedBox(height: 12),
        ],
        DetailSectionTitle(title: context.l10n.appSectionDeveloper),
        const SizedBox(height: 6),
        DetailDeveloperLinks(detail: detail),
      ],
    );
  }
}

/// The page's bar, and the only place the page reaches for [DeviceScope].
///
/// Its own widget because `Scaffold.appBar` needs a [PreferredSizeWidget] and
/// an `AnimatedBuilder` is not one.
///
/// That is the whole of it, and it is worth stating exactly, because the
/// obvious reading is wrong twice over. An `AnimatedBuilder` is its own
/// element and confines its rebuild to its builder *wherever* it is written -
/// it does not need a class around it to stop anywhere. And the scope's
/// device-info poll was the second historical reason for this class and is no
/// longer a reason at all: `DeviceScope.clientOf` registers no dependency, so
/// that read would be safe from the page's own `build`.
///
/// What stays is the type. The bar has to rebuild on the catalog controller -
/// otherwise the delete action goes stale - so an `AnimatedBuilder` has to be
/// above the `QPageAppBar`, and something has to answer `preferredSize` for
/// `Scaffold` before any of it is built. See [_AppDetailPageState.build] and
/// `components/appbar.dart`'s note on [QPageAppBar.preferredSizeWithoutBottom].
/// #344.
class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar({
    required this.controller,
    required this.detail,
    required this.family,
    this.knownCategory,
  });

  final AppsCatalogController controller;
  final AppDetail? detail;
  final CatalogFamily family;
  final AppCategory? knownCategory;

  /// The app's source code, which the bar opens; the catalogue manifest only
  /// when the source is not known.
  static String _sourceUrl(AppDetail detail) {
    final source = detail.links?.sourceCode?.uri ?? '';
    return source.isNotEmpty ? source : detail.links?.manifestUri ?? '';
  }

  @override
  Size get preferredSize => QPageAppBar.preferredSizeWithoutBottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final detail = this.detail;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => QPageAppBar(
        client: DeviceScope.clientOf(context),
        title: detail?.card.name ?? context.l10n.appDetailFallbackTitle,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        actions: [
          if (detail != null) ...[
            if (family.installsAsApp &&
                controller.engine.isInstalled(detail.card))
              QPageAppBarAction(
                tooltip: context.l10n.appDeleteTooltip,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => confirmDeleteApp(
                  context,
                  engine: controller.engine,
                  app: detail.card,
                  category: knownCategory,
                ),
              ),
            if (_sourceUrl(detail).isNotEmpty)
              QPageAppBarAction(
                tooltip: context.l10n.appLinkSource,
                icon: const Icon(Icons.open_in_new),
                onPressed: () =>
                    openUrl(context, _sourceUrl(detail), inApp: false),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.controller,
    required this.family,
    this.knownCategory,
    this.picker,
  });

  final AppDetail detail;
  final AppsCatalogController controller;
  final CatalogFamily family;
  final AppCategory? knownCategory;

  /// Shown when the item offers more than one entry.
  final Widget? picker;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = detail.card;
    final cv = card.currentVersion;
    final cat =
        knownCategory ??
        AppCategory(id: card.categoryId, name: '—', color: 'EBEBEB');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (family.installsAsApp) ...[
              AppIconBadge(url: card.iconUri, size: 64, borderRadius: 14),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CategoryChip(category: cat, selected: true),
                      DetailMeta(
                        label: context.l10n.appMetaVersion,
                        value: cv?.version ?? '—',
                      ),
                      if (family != CatalogFamily.animations)
                        DetailMeta(
                          label: context.l10n.appMetaSize,
                          value: formatBuildSize(detail.buildMetadata?.length),
                        ),
                      if ((card.stats?.downloads ?? 0) > 0)
                        DownloadsBadge(
                          count: card.stats!.downloads,
                          fontSize: 13,
                        ),
                      if (card.authors.isEmpty && card.author.isNotEmpty)
                        DetailMeta(
                          label: context.l10n.appMetaBy,
                          value: card.author,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (picker != null) ...[const SizedBox(height: 14), picker!],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          // The install button and the entry picker are the two things in the
          // body that a controller notification describes, so they are the
          // only ones that listen.
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => AppActionButton(
              engine: controller.engine,
              state: controller.stateFor(card),
              app: card,
              category: knownCategory,
              detail: detail,
              size: AppActionButtonSize.large,
              family: family,
            ),
          ),
        ),
      ],
    );
  }
}
