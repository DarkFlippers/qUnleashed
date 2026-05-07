import 'package:flutter/material.dart';

import '../../../theme.dart';

class ToolItemBadge extends StatelessWidget {
  const ToolItemBadge({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.accent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.accent,
            fontSize: 12,
            height: 1,
          ),
        ),
      ),
    );
  }
}
