import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../models/tool.dart';

class ToolItemText extends StatelessWidget {
  const ToolItemText({
    super.key,
    required this.model,
  });

  final ToolItemModel model;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          model.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          model.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 12,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
