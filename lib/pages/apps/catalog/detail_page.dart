import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/format.dart';
import '../actions.dart';
import 'widgets/states.dart';
import 'widgets/screenshots_viewer.dart';
import '../../../theme/theme.dart';

import 'package:qunleashed/components/appbar.dart';

import '../../../components/changelog_renderer.dart';
import '../../../components/open_url.dart';
import '../data/models/category.dart';
import '../data/models/detail.dart';
import 'controller.dart';
import 'widgets/action_button.dart';
import 'widgets/card.dart';
import 'widgets/category_chip.dart';
import 'widgets/screenshot_frame.dart';
import '../../devices/device_scope.dart';

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({
    super.key,
    required this.alias,
    required this.controller,
    this.knownCategory,
  });

  final String alias;
  final AppsCatalogController controller;
  final AppCategory? knownCategory;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  AppsCatalogController get _ctrl => widget.controller;

  AppDetail? _detail;
  Object? _error;
  bool _loading = true;

  /// The three markdown fields, converted once.
  ///
  /// `buildChangelogHtml` is a markdown parse plus a handful of regex passes -
  /// between 1 and 14 ms per field for a real app's text - and `_load` is the
  /// only thing that changes what goes into it. Converting in `build` instead
  /// repeated all three on every rebuild of the body, and `flutter_html` skips
  /// an equal string anyway, so the work bought nothing.
  String? _shortDescriptionHtml;
  String? _descriptionHtml;
  String? _changelogHtml;

  static String? _htmlOrNull(String? markdown) =>
      markdown == null || markdown.isEmpty
      ? null
      : buildChangelogHtml(markdown);

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
      final d = await _ctrl.api.fetchApp(widget.alias);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _shortDescriptionHtml = _htmlOrNull(
          d.card.currentVersion?.shortDescription,
        );
        _descriptionHtml = _htmlOrNull(d.description);
        _changelogHtml = _htmlOrNull(d.changelog);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Neither the device scope nor the catalog controller is listened to from
  /// here.
  ///
  /// The body carries up to three `SelectionArea`s over `flutter_html`, and a
  /// rebuild throws away a live text selection in them. A selection handle
  /// dragged across that rebuild then crashes inside a gesture callback, where
  /// nothing on this page can catch it. Both of the tickers that used to reach
  /// the whole body now stop at the widget they describe: the scope at
  /// [_DetailAppBar], the controller at the bar's actions and the install
  /// button. `test/app_detail_rebuild_scope_test.dart` holds the mechanism and
  /// the two notification rates. QUNLEASHED-F.
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
        detail: _detail,
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
    if (_error != null || _detail == null) {
      return AppDetailErrorView(onRetry: _load);
    }

    final detail = _detail!;
    final card = detail.card;
    final cv = card.currentVersion;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Header(
          detail: detail,
          controller: _ctrl,
          knownCategory: widget.knownCategory,
        ),
        const SizedBox(height: 18),
        if (cv != null && cv.screenshots.isNotEmpty) ...[
          _ScreenshotsRow(screenshots: cv.screenshots, title: card.name),
          const SizedBox(height: 18),
        ],
        if (_shortDescriptionHtml case final String html) ...[
          _SectionTitle(title: context.l10n.appSectionDescription),
          const SizedBox(height: 6),
          ChangelogRenderer(
            html: html,
            textColor: colors.textPrimary,
            mutedColor: colors.textSecondary,
          ),
        ],
        if (_descriptionHtml case final String html) ...[
          ChangelogRenderer(
            html: html,
            textColor: colors.textPrimary,
            mutedColor: colors.textSecondary,
          ),
          const SizedBox(height: 12),
        ],
        if (_changelogHtml case final String html) ...[
          _SectionTitle(title: context.l10n.appSectionChangelog),
          const SizedBox(height: 6),
          ChangelogRenderer(
            html: html,
            textColor: colors.textPrimary,
            mutedColor: colors.textSecondary,
          ),
          const SizedBox(height: 12),
        ],
        _SectionTitle(title: context.l10n.appSectionDeveloper),
        const SizedBox(height: 6),
        _DeveloperLinks(detail: detail),
      ],
    );
  }
}

/// The page's bar, and the only place the page reaches for [DeviceScope].
///
/// Both of the things that make this rebuild - the scope's device-info poll
/// and the catalog controller - stop here rather than at the page, which is
/// the point of it being its own widget. See [_AppDetailPageState.build].
class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar({
    required this.controller,
    required this.detail,
    this.knownCategory,
  });

  final AppsCatalogController controller;
  final AppDetail? detail;
  final AppCategory? knownCategory;

  @override
  Size get preferredSize => QPageAppBar.preferredSizeWithoutBottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final detail = this.detail;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => QPageAppBar(
        client: DeviceScope.of(context).client,
        title: detail?.card.name ?? context.l10n.appDetailFallbackTitle,
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        actions: [
          if (detail != null) ...[
            if (controller.engine.isInstalled(detail.card))
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
            QPageAppBarAction(
              tooltip: context.l10n.appOpenPageTooltip,
              icon: const Icon(Icons.open_in_new),
              onPressed: () {
                final url = detail.links?.manifestUri ?? '';
                if (url.isNotEmpty) {
                  openUrl(context, url, inApp: false);
                }
              },
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
    this.knownCategory,
  });

  final AppDetail detail;
  final AppsCatalogController controller;
  final AppCategory? knownCategory;

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
            AppIconBadge(url: card.iconUri, size: 64, borderRadius: 14),
            const SizedBox(width: 14),
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
                      _Meta(
                        label: context.l10n.appMetaVersion,
                        value: cv?.version ?? '—',
                      ),
                      _Meta(
                        label: context.l10n.appMetaSize,
                        value: _formatBytes(detail.buildMetadata?.length),
                      ),
                      if (card.author.isNotEmpty)
                        _Meta(
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          // The install button is the one thing in the body that a controller
          // notification describes, so it is the only thing that listens.
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => AppActionButton(
              engine: controller.engine,
              state: controller.stateFor(card),
              app: card,
              category: knownCategory,
              detail: detail,
              size: AppActionButtonSize.large,
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '—';
    return formatBytesScaled(bytes);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotsRow extends StatelessWidget {
  const _ScreenshotsRow({required this.screenshots, required this.title});
  final List<String> screenshots;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: screenshots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return GestureDetector(
            onTap: () => ScreenshotsViewer.open(
              context,
              screenshots: screenshots,
              initialIndex: i,
              title: title,
            ),
            child: ScreenshotFrame(url: screenshots[i]),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: colors.textPrimary,
      ),
    );
  }
}

class _DeveloperLinks extends StatelessWidget {
  const _DeveloperLinks({required this.detail});
  final AppDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final links = detail.links;
    final entries = <_LinkEntry>[
      if (links?.manifestUri != null && links!.manifestUri!.isNotEmpty)
        _LinkEntry(context.l10n.appLinkManifest, links.manifestUri!),
      if (links?.sourceCode != null && links!.sourceCode!.uri.isNotEmpty)
        _LinkEntry(context.l10n.appLinkSource, links.sourceCode!.uri),
      if (links?.bundleUri != null && links!.bundleUri!.isNotEmpty)
        _LinkEntry(context.l10n.appLinkBundle, links.bundleUri!),
    ];

    if (entries.isEmpty) {
      return Text(
        context.l10n.appNoDeveloperLinks,
        style: TextStyle(color: colors.textMuted, fontSize: 13),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => openUrl(context, e.url, inApp: false),
              child: Row(
                children: [
                  Icon(Icons.link, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    e.label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LinkEntry {
  final String label;
  final String url;
  const _LinkEntry(this.label, this.url);
}
