import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/device_shell.dart';
import '../widgets/page_placeholder.dart';
import 'widgets/tools_logs_card.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({
    super.key,
    required this.connected,
    required this.onOpenLogs,
  });

  final bool connected;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) {
    if (!connected) {
      return const PagePlaceholder(
        title: 'Tools',
      );
    }

    final colors = context.appColors;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      children: [
        FlipperPageCard(
          child: Column(
            children: [
              ToolsLogsCard(
                iconColor: colors.textPrimary,
                onTap: onOpenLogs,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
