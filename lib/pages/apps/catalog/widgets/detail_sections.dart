import 'package:flutter/material.dart';

import '../../../../components/changelog_renderer.dart';
import '../../../../components/format.dart';
import '../../../../components/open_url.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../../data/models/detail.dart';
import 'screenshot_frame.dart';
import 'screenshots_viewer.dart';

String formatBuildSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  return formatBytesScaled(bytes);
}

class DetailMarkdown extends StatefulWidget {
  const DetailMarkdown({super.key, required this.source});

  final String source;

  @override
  State<DetailMarkdown> createState() => _DetailMarkdownState();
}

class _DetailMarkdownState extends State<DetailMarkdown> {
  late String _html;

  @override
  void initState() {
    super.initState();
    _html = buildChangelogHtml(widget.source);
  }

  @override
  void didUpdateWidget(DetailMarkdown old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _html = buildChangelogHtml(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ChangelogRenderer(
      html: _html,
      textColor: colors.textPrimary,
      mutedColor: colors.textSecondary,
    );
  }
}

class DetailMeta extends StatelessWidget {
  const DetailMeta({super.key, required this.label, required this.value});
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

class DetailScreenshotsRow extends StatelessWidget {
  const DetailScreenshotsRow({
    super.key,
    required this.screenshots,
    required this.title,
  });
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

class DetailSectionTitle extends StatelessWidget {
  const DetailSectionTitle({super.key, required this.title});
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

class DetailDeveloperLinks extends StatelessWidget {
  const DetailDeveloperLinks({super.key, required this.detail});
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
