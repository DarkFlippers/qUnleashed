import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../controller.dart';
import '../widgets/empty_view.dart';
import '../widgets/key_actions_sheet.dart';
import '../widgets/key_card.dart';

/// Lists keys deleted remotely but still cached on this device, with restore.
class DeletedPage extends StatelessWidget {
  const DeletedPage({super.key, required this.controller});

  final ArchiveController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keys = controller.deletedKeys();
        return Scaffold(
          backgroundColor: colors.background,
          appBar: QPageAppBar(
            title: 'Deleted',
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
          ),
          body: keys.isEmpty
              ? const ArchiveEmptyView(
                  icon: Icons.delete_outline,
                  title: 'Nothing here',
                  subtitle: 'Deleted keys are kept on this device until purged',
                )
              : RefreshIndicator(
                  color: colors.accent,
                  onRefresh: controller.refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => KeyCard(
                      flipperKey: keys[i],
                      onTap: () =>
                          KeyActionsSheet.show(context, controller, keys[i]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
