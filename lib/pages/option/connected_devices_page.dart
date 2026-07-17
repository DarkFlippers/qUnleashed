import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class ConnectedDevicesSettingsPage extends StatelessWidget {
  const ConnectedDevicesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Connected devices'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
      ),
      body: Center(
        child: Text(
          'Nothing here yet',
          style: TextStyle(fontSize: 13, color: colors.textMuted),
        ),
      ),
    );
  }
}
