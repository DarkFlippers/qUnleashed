import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../../data/models/card.dart';
import '../../data/models/category.dart';
import '../../../../components/remote_image.dart';
import 'category_chip.dart';
import 'screenshot_frame.dart';
import 'screenshots_viewer.dart';

class AppCardView extends StatelessWidget {
  const AppCardView({
    super.key,
    required this.app,
    required this.action,
    this.category,
    this.onTap,
    this.padding = 12,
    this.showScreenshots = true,
  });

  /// Grid row height of a card without the screenshot strip, at the current
  /// text scale: header, two lines of description, padding.
  static double compactHeight(BuildContext context, {double padding = 12}) =>
      padding * 2 + 48 + 8 + _Description.heightOf(context);

  final AppCard app;
  final AppCategory? category;
  final Widget action;
  final VoidCallback? onTap;
  final double padding;

  /// Off for families whose screens cannot be compared side by side.
  final bool showScreenshots;

  @override
  Widget build(BuildContext context) {
    final shots = showScreenshots ? app.screenshots : const <String>[];
    return CatalogCardFrame(
      onTap: onTap,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(app: app, category: category, action: action),
          const SizedBox(height: 8),
          _Description(text: app.shortDescription),
          if (shots.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ScreenshotsStrip(screenshots: shots, title: app.name),
          ],
        ],
      ),
    );
  }
}

class ScreenCardView extends StatelessWidget {
  const ScreenCardView({
    super.key,
    required this.app,
    required this.preview,
    required this.action,
    this.category,
    this.onTap,
  });

  static const double _padding = 12;
  static const double _gap = 10;
  static const double _rowHeight = 32;
  static const double _categoryHeight = 18;
  static const double _previewFrame = 12;

  static double heightFor(double width) {
    final screen = width - _padding * 2;
    final preview = (screen - _previewFrame) / 2 + _previewFrame;
    return _padding * 2 + preview + _gap + _rowHeight + _categoryHeight;
  }

  final AppCard app;
  final Widget preview;
  final AppCategory? category;
  final Widget action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return CatalogCardFrame(
      onTap: onTap,
      padding: _padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          preview,
          const SizedBox(height: _gap),
          SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                action,
              ],
            ),
          ),
          SizedBox(
            height: _categoryHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _CardMeta(category: category, stats: app.stats),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogCardFrame extends StatefulWidget {
  const CatalogCardFrame({
    super.key,
    required this.child,
    required this.padding,
    this.onTap,
  });

  final Widget child;
  final double padding;
  final VoidCallback? onTap;

  @override
  State<CatalogCardFrame> createState() => _CatalogCardFrameState();
}

class _CatalogCardFrameState extends State<CatalogCardFrame> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(33),
                    blurRadius: 11,
                    offset: const Offset(0, 1),
                  ),
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.all(widget.padding),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.text});

  final String text;

  static const double _fontSize = 12;
  static const double _lineHeight = 1.3;
  static const int _lines = 2;

  static TextStyle _style(Color color) =>
      TextStyle(fontSize: _fontSize, height: _lineHeight, color: color);

  static double heightOf(BuildContext context) {
    final probe = TextPainter(
      text: TextSpan(text: '\n', style: _style(const Color(0xFF000000))),
      maxLines: _lines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = probe.size.height;
    probe.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context.appColors.textSecondary);
    return SizedBox(
      height: heightOf(context),
      child: Text(
        text,
        maxLines: _lines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.app,
    required this.category,
    required this.action,
  });

  final AppCard app;
  final AppCategory? category;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppIconBadge(url: app.iconUri, size: 48),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              _CardMeta(category: category, stats: app.stats),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: action),
        ),
      ],
    );
  }
}

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.url,
    this.size = 48,
    this.borderRadius = 11,
  });

  final String url;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final style = QIconBadgeStyle.of(context, context.appColors.accent);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: SizedBox(
        width: size * 0.6,
        height: size * 0.6,
        child: FlipperRemoteImage(
          url: url,
          fit: BoxFit.contain,
          tint: style.foreground,
          placeholderColor: style.foreground,
        ),
      ),
    );
  }
}

String formatCount(int value) {
  const units = ['', 'K', 'M', 'B'];
  if (value < 1000) return '$value';
  var scaled = value.toDouble();
  var unit = 0;
  while (scaled >= 1000 && unit < units.length - 1) {
    scaled /= 1000;
    unit++;
  }
  var text = scaled.toStringAsFixed(scaled < 10 ? 1 : 0);
  if (text == '1000' && unit < units.length - 1) {
    text = '1';
    unit++;
  }
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '$text${units[unit]}';
}

class DownloadsBadge extends StatelessWidget {
  const DownloadsBadge({super.key, required this.count, this.fontSize = 11});

  final int count;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.download_rounded, size: fontSize + 1, color: color),
        const SizedBox(width: 2),
        Text(
          formatCount(count),
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CardMeta extends StatelessWidget {
  const _CardMeta({required this.category, required this.stats});

  final AppCategory? category;
  final AppStats? stats;

  @override
  Widget build(BuildContext context) {
    final downloads = stats?.downloads ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _CategoryInline(category: category)),
        if (downloads > 0) ...[
          if (category != null) const SizedBox(width: 8),
          DownloadsBadge(count: downloads),
        ],
      ],
    );
  }
}

class _CategoryInline extends StatelessWidget {
  const _CategoryInline({required this.category});
  final AppCategory? category;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cat = category;
    if (cat == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CategoryIcon(
          category: cat,
          color: colors.textSecondary,
          size: 12,
          gap: 4,
        ),
        Flexible(
          child: Text(
            cat.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScreenshotsStrip extends StatelessWidget {
  const _ScreenshotsStrip({required this.screenshots, required this.title});
  final List<String> screenshots;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: screenshots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => ScreenshotsViewer.open(
            context,
            screenshots: screenshots,
            initialIndex: i,
            title: title,
          ),
          child: ScreenshotFrame(url: screenshots[i]),
        ),
      ),
    );
  }
}
