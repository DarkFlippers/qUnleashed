import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';
import '../controller.dart';

class SyncProgressView extends StatelessWidget {
  const SyncProgressView({super.key, required this.progress});

  final SyncProgress? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final p = progress;
    final ratio = (p == null || p.total == 0) ? null : p.current / p.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p == null
                      ? 'Syncing...'
                      : 'Syncing ${p.current}/${p.total}  ${p.fileName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              color: colors.accent,
              backgroundColor: colors.divider,
            ),
          ),
        ],
      ),
    );
  }
}
