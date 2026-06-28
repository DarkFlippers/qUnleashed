import 'package:flutter/material.dart';

import '../../../../components/icon.dart';
import '../../../../theme/theme.dart';
import '../models/tool.dart';
import 'tool_item.dart';

class ToolCardView extends StatelessWidget {
  const ToolCardView({super.key, required this.model});

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
        child: switch (model) {
          ToolCardGroup group => _GroupBody(group: group),
          ToolCard card => ToolItem(model: card.item),
        },
      ),
    );
  }
}

class _GroupBody extends StatelessWidget {
  const _GroupBody({required this.group});

  final ToolCardGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(header: group.header),
        for (final (index, item) in group.items.indexed) ...[
          if (index > 0) _ItemDivider(),
          ToolItem(model: item),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.header});

  final ToolCardHeader header;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: QIcon(
            asset: header.iconAsset,
            color: header.iconColor,
            size: 24,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              header.title,
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
    );
  }
}

class _ItemDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 12,
      endIndent: 12,
      color: context.appColors.divider,
    );
  }
}
