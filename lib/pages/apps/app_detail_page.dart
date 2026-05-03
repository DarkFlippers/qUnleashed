import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/changelog_renderer.dart';
import '../devices/remote_control_page.dart';
import 'apps_catalog_api.dart';
import 'apps_install_service.dart';
import 'models/app_card.dart';
import 'models/app_category.dart';
import 'models/app_detail.dart';
import 'screenshots_viewer.dart';
import 'widgets/app_action_button.dart';
import 'widgets/category_chip.dart';
import 'widgets/flipper_image.dart';
import 'widgets/screenshot_frame.dart';

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({
    super.key,
    required this.alias,
    required this.api,
    required this.installService,
    this.knownCategory,
  });

  final String alias;
  final AppsCatalogApi api;
  final AppsInstallService installService;
  final AppCategory? knownCategory;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  AppDetail? _detail;
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
      final d = await widget.api.fetchApp(widget.alias);
      if (!mounted) return;
      setState(() {
        _detail = d;
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

  void _onLaunched() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
  }

  Future<void> _confirmDelete(AppCard card, AppCategory? cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete app?'),
        content: Text('Remove "${card.name}" from your Flipper?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await widget.installService.uninstall(card, category: cat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: widget.installService,
      builder: (context, _) => Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          title: Text(_detail?.card.name ?? 'App'),
          actions: [
            if (_detail != null) ...[
              if (widget.installService.isInstalled(_detail!.card))
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(_detail!.card, widget.knownCategory),
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  final url = _detail!.links?.manifestUri ?? '';
                  if (url.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
              ),
            ],
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null || _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 48),
            const SizedBox(height: 8),
            Text('Failed to load app', style: TextStyle(color: colors.textPrimary)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final detail = _detail!;
    final card = detail.card;
    final cv = card.currentVersion;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Header(
          detail: detail,
          knownCategory: widget.knownCategory,
          installService: widget.installService,
          onLaunched: _onLaunched,
        ),
        const SizedBox(height: 18),
        if (cv != null && cv.screenshots.isNotEmpty) ...[
          _ScreenshotsRow(
            screenshots: cv.screenshots,
            title: card.name,
          ),
          const SizedBox(height: 18),
        ],
        if (cv != null && cv.shortDescription.isNotEmpty) ...[
          _SectionTitle(title: 'Description'),
          const SizedBox(height: 6),
          ChangelogRenderer(
            html: buildChangelogHtml(cv.shortDescription),
            textColor: colors.textPrimary,
            mutedColor: colors.textSecondary,
          ),
        ],
        if (detail.description.isNotEmpty) ...[
          ChangelogRenderer(
            html: buildChangelogHtml(detail.description),
            textColor: colors.textPrimary,
            mutedColor: colors.textSecondary,
          ),
          const SizedBox(height: 12),
        ],
        if (detail.changelog.isNotEmpty) ...[
          _SectionTitle(title: 'Changelog'),
          const SizedBox(height: 6),
          ChangelogRenderer(
            html: buildChangelogHtml(detail.changelog),
            textColor: colors.textPrimary,
            mutedColor: colors.textSecondary,
          ),
          const SizedBox(height: 12),
        ],
        _SectionTitle(title: 'Developer'),
        const SizedBox(height: 6),
        _DeveloperLinks(detail: detail),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.installService,
    this.knownCategory,
    this.onLaunched,
  });

  final AppDetail detail;
  final AppsInstallService installService;
  final AppCategory? knownCategory;
  final VoidCallback? onLaunched;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = detail.card;
    final cv = card.currentVersion;
    final cat = knownCategory ??
        AppCategory(id: card.categoryId, name: '—', color: 'EBEBEB');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.accent,
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: FlipperRemoteImage(url: card.iconUri, fit: BoxFit.contain),
              ),
            ),
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
                      _Meta(label: 'Version', value: cv?.version ?? '—'),
                      _Meta(label: 'Size', value: _formatBytes(detail.buildMetadata?.length)),
                      if (card.author.isNotEmpty)
                        _Meta(label: 'By', value: card.author),
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
          child: AppActionButton(
            service: installService,
            app: card,
            category: knownCategory,
            detail: detail,
            onLaunched: onLaunched,
            size: AppActionButtonSize.large,
          ),
        ),
      ],
    );
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    var b = bytes.toDouble();
    var i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
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
            child: AspectRatio(
              aspectRatio: 256 / 128,
              child: ScreenshotFrame(url: screenshots[i]),
            ),
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
        _LinkEntry('Manifest', links.manifestUri!),
      if (links?.sourceCode != null && links!.sourceCode!.uri.isNotEmpty)
        _LinkEntry('Source code', links.sourceCode!.uri),
      if (links?.bundleUri != null && links!.bundleUri!.isNotEmpty)
        _LinkEntry('Bundle', links.bundleUri!),
    ];

    if (entries.isEmpty) {
      return Text(
        'No developer links provided',
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
              onTap: () {
                Clipboard.setData(ClipboardData(text: e.url));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${e.label} link copied')),
                );
              },
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
