import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/app_card.dart';
import '../models/app_category.dart';
import 'flipper_image.dart';
import 'screenshot_frame.dart';

class AppCardView extends StatefulWidget {
  const AppCardView({
    super.key,
    required this.app,
    this.category,
    this.action,
    this.onTap,
    this.padding = 12,
  });

  final AppCard app;
  final AppCategory? category;
  final Widget? action;
  final VoidCallback? onTap;
  final double padding;

  @override
  State<AppCardView> createState() => _AppCardViewState();
}

class _AppCardViewState extends State<AppCardView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final shots = widget.app.screenshots;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CardHeader(
                    app: widget.app,
                    category: widget.category,
                    action: widget.action,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.app.shortDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (shots.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ScreenshotsStrip(screenshots: shots),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.app, required this.category, required this.action});

  final AppCard app;
  final AppCategory? category;
  final Widget? action;

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
              _CategoryInline(category: category),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 88,
          child: Align(
            alignment: Alignment.centerRight,
            child: action ?? const _DefaultInstallButton(),
          ),
        ),
      ],
    );
  }
}

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({super.key, required this.url, this.size = 48});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.accent,
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: FlipperRemoteImage(url: url, fit: BoxFit.contain),
      ),
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
        if (cat.iconUri != null && cat.iconUri!.isNotEmpty) ...[
          SizedBox(
            width: 12,
            height: 12,
            child: SvgPicture.network(
              cat.iconUri!,
              colorFilter: ColorFilter.mode(colors.textSecondary, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 4),
        ],
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
  const _ScreenshotsStrip({required this.screenshots});
  final List<String> screenshots;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: screenshots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          return SizedBox(
            width: 168,
            child: ScreenshotFrame(url: screenshots[i]),
          );
        },
      ),
    );
  }
}

class _DefaultInstallButton extends StatelessWidget {
  const _DefaultInstallButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 32,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'INSTALL',
        style: TextStyle(
          color: colors.onAccent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
