import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/format.dart';
import '../../../theme/theme.dart';
import '../../../services/assembler/controller.dart';

class AssemblerProgressPanel extends StatelessWidget {
  const AssemblerProgressPanel({
    super.key,
    required this.controller,
    this.idleLabel = 'Idle',
  });

  final AssemblerController controller;
  final String idleLabel;

  static String jobLabel(AssemblerJob job) => switch (job) {
    AssemblerJob.none => '',
    AssemblerJob.sdk => 'Downloading SDK',
    AssemblerJob.toolchain => 'Downloading toolchain',
    AssemblerJob.build => 'Building from source',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final progress = controller.progress;
        final busy = controller.busy;
        final fraction = progress?.fraction;
        final title = progress?.title.isNotEmpty == true
            ? progress!.title
            : (busy ? jobLabel(controller.job) : idleLabel);

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(kGroupedOuterRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: busy ? colors.textPrimary : colors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fraction == null
                        ? (busy ? '…' : '')
                        : '${(fraction * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: busy ? fraction : 0,
                  minHeight: 6,
                  backgroundColor: colors.divider,
                  color: colors.accent,
                ),
              ),
              if (progress?.total != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_size(progress!.current)} / ${_size(progress.total!)}',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _size(int bytes) => formatBytes(bytes, gigabytes: false);
}
