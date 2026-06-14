import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme.dart';
import '../models/tool.dart';
import '../preview/tools.dart';
import 'tool_item_badge.dart';
import 'tool_item_text.dart';

class ToolItem extends StatelessWidget {
  const ToolItem({
    super.key,
    required this.model,
    this.alignWithPreview = false,
  });

  final ToolItemModel model;
  final bool alignWithPreview;

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
              _ItemLeading(model: model, alignWithPreview: alignWithPreview),
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

class _ItemLeading extends StatelessWidget {
  const _ItemLeading({required this.model, required this.alignWithPreview});

  final ToolItemModel model;
  final bool alignWithPreview;

  @override
  Widget build(BuildContext context) {
    final preview = model.preview;
    if (preview != null) {
      return SizedBox(width: 64, height: 64, child: ToolPreview(type: preview));
    }
    final color = model.iconColor ?? context.appColors.textPrimary;
    final icon = QIconBadge(asset: model.iconAsset!, color: color);
    if (!alignWithPreview) return icon;
    return SizedBox(width: 64, child: Center(child: icon));
  }
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
