import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';
import '../../components/navigation.dart';
import '../../components/notification.dart';
import '../../services/assembler/controller.dart';
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
        title: Text(context.l10n.fliblerConsoleTitle),
        backgroundColor: colors.background,
        surfaceTintColor: colors.transparent,
        actions: [
          IconButton(
            tooltip: context.l10n.fliblerTitle,
            icon: Icon(Icons.settings_outlined, color: colors.textPrimary),
            onPressed: () =>
                openRoute(context, AppRoute.assemblerSettings, args: true),
          ),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => IconButton(
              tooltip: context.l10n.fliblerVerbose,
              icon: Icon(
                Icons.bug_report_outlined,
                color: controller.verbose ? colors.accent : colors.textMuted,
              ),
              onPressed: () => controller.setVerbose(!controller.verbose),
            ),
          ),
          IconButton(
            tooltip: context.l10n.fliblerCopyLog,
            icon: Icon(Icons.copy_all_outlined, color: colors.textPrimary),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: controller.logAsText()),
              );
              if (context.mounted) {
                QNotification.show(
                  context,
                  message: context.l10n.fliblerLogCopied,
                );
              }
            },
          ),
          IconButton(
            tooltip: context.l10n.fliblerClearLog,
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
