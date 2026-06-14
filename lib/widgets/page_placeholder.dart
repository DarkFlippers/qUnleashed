import 'package:flutter/material.dart';

import '../theme/theme.dart';

class PagePlaceholder extends StatelessWidget {
  const PagePlaceholder({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          color: colors.textMuted,
        ),
      ),
    );
  }
}
