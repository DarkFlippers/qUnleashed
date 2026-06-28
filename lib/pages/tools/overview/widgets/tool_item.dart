import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../models/tool.dart';
import 'tool_item_badge.dart';
import 'tool_item_text.dart';

class ToolItem extends StatelessWidget {
  const ToolItem({super.key, required this.model});

  final ToolItemModel model;

  @override
  Widget build(BuildContext context) {
    final onTap = _resolveTap(context, model);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              QIconBadge(asset: model.iconAsset, color: model.iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: ToolItemText(
                  title: model.title,
                  description: model.description,
                ),
              ),
              _ItemTrailing(badge: model.badge),
            ],
          ),
        ),
      ),
    );
  }
}

VoidCallback? _resolveTap(BuildContext context, ToolItemModel model) {
  final onTap = model.onTap;
  if (onTap != null) return () => onTap(context);

  final routeBuilder = model.routeBuilder;
  if (routeBuilder != null) {
    return () =>
        Navigator.of(context).push(MaterialPageRoute(builder: routeBuilder));
  }
  return null;
}

class _ItemTrailing extends StatelessWidget {
  const _ItemTrailing({this.badge});

  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) ToolItemBadge(label: badge!),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: QIcon(
            asset: 'assets/ic/nav/navigate-tool.svg',
            color: colors.textMuted,
            size: 16,
          ),
        ),
      ],
    );
  }
}
