import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../widgets/open_url.dart';

String buildChangelogHtml(String data) {
  return _sanitizeHtml(
    md.markdownToHtml(
      _normalizeEscapedHtml(data),
      extensionSet: md.ExtensionSet.gitHubWeb,
    ),
  );
}

class ChangelogRenderer extends StatelessWidget {
  const ChangelogRenderer({
    super.key,
    required this.html,
    this.textColor,
    this.mutedColor,
  });

  final String html;
  final Color? textColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final baseTextColor = textColor ?? Theme.of(context).colorScheme.onSurface;
    final secondaryColor = mutedColor ?? baseTextColor.withValues(alpha: 0.72);

    return SelectionArea(
      child: Html(
        data: html,
        onLinkTap: (url, attrs, element) {
          if (url == null || url.isEmpty) return;
          openUrl(context, url);
        },
        extensions: [
          TagWrapExtension(
            tagsToWrap: const {'table'},
            builder: (child) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          ),
          const TableHtmlExtension(),
        ],
        style: {
          'html': Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            color: baseTextColor,
            fontSize: FontSize(14),
            lineHeight: const LineHeight(1.45),
          ),
          'body': Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
          ),
          'p': Style(
            margin: Margins.only(bottom: 14),
          ),
          'ul': Style(
            margin: Margins.only(bottom: 14, left: 12),
            padding: HtmlPaddings.zero,
          ),
          'ol': Style(
            margin: Margins.only(bottom: 14, left: 12),
            padding: HtmlPaddings.zero,
          ),
          'li': Style(
            margin: Margins.only(bottom: 6),
            color: baseTextColor,
          ),
          'h1': _headingStyle(baseTextColor, 24),
          'h2': _headingStyle(baseTextColor, 20),
          'h3': _headingStyle(baseTextColor, 18),
          'h4': _headingStyle(baseTextColor, 16),
          'h5': _headingStyle(baseTextColor, 15),
          'h6': _headingStyle(baseTextColor, 14),
          'hr': Style(
            margin: Margins.symmetric(vertical: 14),
            border: Border(
              bottom: BorderSide(
                color: secondaryColor.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
          ),
          'blockquote': Style(
            margin: Margins.only(bottom: 14),
            padding: HtmlPaddings.only(left: 12),
            color: secondaryColor,
            border: Border(
              left: BorderSide(
                color: secondaryColor.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
          ),
          'code': Style(
            fontFamily: 'monospace',
            backgroundColor: Colors.black.withValues(alpha: 0.06),
            padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 2),
          ),
          'pre': Style(
            margin: Margins.only(bottom: 14),
            padding: HtmlPaddings.all(12),
            backgroundColor: Colors.black.withValues(alpha: 0.06),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          'a': Style(
            color: baseTextColor,
            textDecoration: TextDecoration.underline,
          ),
          'table': Style(
            margin: Margins.only(bottom: 14),
            backgroundColor: Colors.black.withValues(alpha: 0.04),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          'tr': Style(
            border: Border(
              bottom: BorderSide(
                color: Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          'th': Style(
            padding: HtmlPaddings.all(8),
            backgroundColor: Colors.black.withValues(alpha: 0.05),
            fontWeight: FontWeight.w700,
            color: baseTextColor,
            verticalAlign: VerticalAlign.bottom,
          ),
          'td': Style(
            padding: HtmlPaddings.all(8),
            color: baseTextColor,
            verticalAlign: VerticalAlign.bottom,
          ),
        },
      ),
    );
  }

  Style _headingStyle(Color color, double size) {
    return Style(
      margin: Margins.only(bottom: 10, top: 4),
      color: color,
      fontSize: FontSize(size),
      fontWeight: FontWeight.w700,
      lineHeight: const LineHeight(1.2),
    );
  }
}

String _normalizeEscapedHtml(String text) {
  return text
      .replaceAll(r'\u003C', '<')
      .replaceAll(r'\u003E', '>')
      .replaceAll(r'\u003D', '=')
      .replaceAll(r'\n', '\n');
}

String _sanitizeHtml(String html) {
  return html
      .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '')
      .replaceAll(
        RegExp(r'<(/?)(div|span)([^>]*)align="[^"]*"([^>]*)>', caseSensitive: false),
        '<\$1\$2\$3\$4>',
      )
      .replaceAll(
        RegExp(r'\s(style|width|height|valign|vertical-align)="[^"]*"', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'<a([^>]*)>\s*</a>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<div>\s*</div>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<span>\s*</span>', caseSensitive: false), '');
}
