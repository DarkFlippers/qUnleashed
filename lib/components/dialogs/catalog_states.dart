import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class CatalogEmptyView extends StatelessWidget {
  const CatalogEmptyView({super.key, required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apps, size: 48, color: colors.textMuted),
          const SizedBox(height: 8),
          Text(
            failed ? 'Failed to load apps' : 'No apps found',
            style: TextStyle(color: colors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class AppDetailErrorView extends StatelessWidget {
  const AppDetailErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: colors.danger, size: 48),
          const SizedBox(height: 8),
          Text(
            'Failed to load app',
            style: TextStyle(color: colors.textPrimary),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
