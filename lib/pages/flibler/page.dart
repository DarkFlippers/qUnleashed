import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import '../../components/notification.dart';
import '../../services/assembler/controller.dart';
import 'settings_page.dart';
import 'widgets/log_view.dart';
import 'widgets/progress_panel.dart';

class AssemblerConsolePage extends StatelessWidget {
  const AssemblerConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final controller = AssemblerController.instance;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Assembler'),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Assembler settings',
            icon: Icon(Icons.settings_outlined, color: colors.textPrimary),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AssemblerSettingsPage(fromConsole: true),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => IconButton(
              tooltip: 'Verbose output',
              icon: Icon(
                Icons.bug_report_outlined,
                color: controller.verbose ? colors.accent : colors.textMuted,
              ),
              onPressed: () => controller.setVerbose(!controller.verbose),
            ),
          ),
          IconButton(
            tooltip: 'Copy log',
            icon: Icon(Icons.copy_all_outlined, color: colors.textPrimary),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: controller.logAsText()),
              );
              if (context.mounted) {
                QNotification.show(context, message: 'Log copied');
              }
            },
          ),
          IconButton(
            tooltip: 'Clear log',
            icon: Icon(Icons.delete_outline, color: colors.textPrimary),
            onPressed: controller.clearLog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: Column(
            children: [
              AssemblerProgressPanel(controller: controller),
              const SizedBox(height: 12),
              Expanded(child: AssemblerLogView(controller: controller)),
            ],
          ),
        ),
      ),
    );
  }
}
