import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/tool.dart';
import 'tool_item.dart';
import 'tool_item_badge.dart';

class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.model,
  });

  final ToolCardModel model;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: model.compact
            ? _CompactBody(model: model)
            : _FullBody(model: model),
      ),
    );
  }
}

class _FullBody extends StatelessWidget {
  const _FullBody({required this.model});

  final ToolCardModel model;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: SvgPicture.asset(
                model.iconAsset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  model.iconColor,
                  BlendMode.srcIn,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  model.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        ToolItem(model: model.tool),
      ],
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({required this.model});

  final ToolCardModel model;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tool = model.tool;
    final Future<void> Function(BuildContext context)? onTap = tool.onTap ??
        (tool.routeBuilder == null
            ? null
            : (context) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: tool.routeBuilder!),
                );
              });
    return InkWell(
      onTap: onTap == null ? null : () => onTap(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SvgPicture.asset(
                model.iconAsset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  model.iconColor,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    model.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (tool.badge != null) ToolItemBadge(label: tool.badge!),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SvgPicture.asset(
                'assets/flipper_svg/tools/ic_navigate.svg',
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(
                  colors.textMuted,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
