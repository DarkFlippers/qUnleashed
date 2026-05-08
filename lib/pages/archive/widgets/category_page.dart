import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../archive_controller.dart';
import '../models/archive_category.dart';
import '../models/archive_key.dart';
import 'archive_empty_view.dart';
import 'key_actions_sheet.dart';
import 'key_card.dart';

class CategoryPage extends StatelessWidget {
  const CategoryPage({
    super.key,
    required this.controller,
    required this.category,
  });

  final ArchiveController controller;
  final ArchiveCategory category;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keys = controller.keysFor(category);
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: Text(category.title),
          ),
          body: keys.isEmpty
              ? ArchiveEmptyView(
                  icon: category.icon,
                  title: 'No ${category.title} keys',
                  subtitle: controller.isConnected
                      ? 'Pull to refresh'
                      : 'Connect a Flipper to see keys',
                )
              : RefreshIndicator(
                  color: colors.accent,
                  onRefresh: controller.refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildKey(context, keys[i]),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildKey(BuildContext context, ArchiveKey k) {
    return KeyCard(
      flipperKey: k,
      onTap: () => KeyActionsSheet.show(context, controller, k),
    );
  }
}

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
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: const Text('Deleted'),
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
                      onTap: () => KeyActionsSheet.show(context, controller, keys[i]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
