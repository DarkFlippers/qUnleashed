import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../theme.dart';
import '../controller.dart';

class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final RemoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final asset = entry.isDir
        ? 'assets/flipper_svg/archive/ic_folder.svg'
        : 'assets/flipper_svg/archive/ic_file.svg';
    final tint = entry.isDir ? colors.accent : colors.textSecondary;
    final muted = entry.isHidden;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              SvgPicture.asset(
                asset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  muted ? colors.textMuted : tint,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted ? colors.textMuted : colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!entry.isDir)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatSize(entry.size),
                          style: TextStyle(color: colors.textMuted, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                entry.isDir ? Icons.chevron_right : Icons.more_vert,
                color: colors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
