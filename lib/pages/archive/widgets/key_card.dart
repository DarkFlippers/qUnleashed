import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/archive_key.dart';

class KeyCard extends StatelessWidget {
  const KeyCard({super.key, required this.flipperKey, required this.onTap});

  final ArchiveKey flipperKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: flipperKey.category.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SvgPicture.asset(
                  flipperKey.category.asset,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    flipperKey.category.color,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            flipperKey.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (flipperKey.isAutosave) ...[
                          const SizedBox(width: 6),
                          const _AutosaveBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${flipperKey.category.title} · ${_subtitle(flipperKey)}',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(state: flipperKey.state),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(ArchiveKey k) {
    switch (k.state) {
      case ArchiveKeyState.synced:
        return 'synced';
      case ArchiveKeyState.remoteOnly:
        return 'on device';
      case ArchiveKeyState.localOnly:
        return 'on phone';
      case ArchiveKeyState.deleted:
        return 'deleted from device';
    }
  }
}

class _AutosaveBadge extends StatelessWidget {
  const _AutosaveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 10, color: colors.info),
          const SizedBox(width: 2),
          Text(
            'AUTOSAVE',
            style: TextStyle(
              color: colors.info,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final ArchiveKeyState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final IconData icon;
    final Color tint;
    switch (state) {
      case ArchiveKeyState.synced:
        icon = Icons.cloud_done_outlined;
        tint = colors.success;
        break;
      case ArchiveKeyState.remoteOnly:
        icon = Icons.cloud_outlined;
        tint = colors.info;
        break;
      case ArchiveKeyState.localOnly:
        icon = Icons.smartphone;
        tint = colors.textMuted;
        break;
      case ArchiveKeyState.deleted:
        icon = Icons.delete_outline;
        tint = colors.danger;
        break;
    }
    return Icon(icon, color: tint, size: 20);
  }
}
