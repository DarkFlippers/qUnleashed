import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/tool.dart';
import 'tool_item_badge.dart';
import 'tool_item_text.dart';
import 'tool_preview.dart';

class ToolItem extends StatelessWidget {
  const ToolItem({
    super.key,
    required this.model,
  });

  final ToolItemModel model;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: model.routeBuilder == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: model.routeBuilder!),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: ToolPreview(type: model.preview!),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ToolItemText(model: model),
              ),
              if (model.badge != null) ToolItemBadge(label: model.badge!),
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
      ),
    );
  }
}
