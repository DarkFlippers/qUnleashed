import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';

class AppsPlaceholder extends StatelessWidget {
  const AppsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Text(
        'Apps',
        style: TextStyle(fontSize: 20, color: colors.textMuted),
      ),
    );
  }
}
