import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/app_card.dart';
import '../models/app_category.dart';
import 'screenshot_frame.dart';

class AppCardView extends StatefulWidget {
  const AppCardView({
    super.key,
    required this.app,
    this.category,
    this.action,
    this.onTap,
    this.cardWidth = 256,
    this.padding = 12,
  });

  final AppCard app;
  final AppCategory? category;
  final Widget? action;
  final VoidCallback? onTap;
  final double cardWidth;
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
    final firstScreenshot = shots.isNotEmpty ? shots.first : widget.app.iconUri;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: widget.cardWidth + widget.padding * 2,
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
                  ScreenshotFrame(url: firstScreenshot),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CategoryInline(category: widget.category),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          widget.app.shortDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: widget.action ?? const _DefaultInstallButton(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
            width: 14,
            height: 14,
            child: SvgPicture.network(
              cat.iconUri!,
              colorFilter: ColorFilter.mode(colors.textSecondary, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          cat.name,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
