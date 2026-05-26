import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme.dart';
import '../models/key.dart';

class KeyCard extends StatelessWidget {
  const KeyCard({
    super.key,
    required this.flipperKey,
    required this.onTap,
    this.onToggleStar,
  });

  final ArchiveKey flipperKey;
  final VoidCallback onTap;
  final VoidCallback? onToggleStar;

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
                    Text(
                      flipperKey.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _SubtitleRow(
                      category: flipperKey.category.title,
                      subFolder: flipperKey.subFolder,
                      muted: colors.textMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(state: flipperKey.state),
              if (onToggleStar != null) ...[
                const SizedBox(width: 8),
                _StarButton(onTap: onToggleStar!, starred: flipperKey.favorite),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({required this.onTap, required this.starred});

  final VoidCallback onTap;
  final bool starred;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: starred
              ? Colors.amber.withValues(alpha: 0.15)
              : context.appColors.background.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          starred ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 18,
          color: starred ? Colors.amber.shade600 : context.appColors.textMuted,
        ),
      ),
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({
    required this.category,
    required this.subFolder,
    required this.muted,
  });

  final String category;
  final String subFolder;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: muted, fontSize: 12);
    if (subFolder.isEmpty) {
      return Text(category, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Row(
      children: [
        Flexible(
          child: Text(category, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(subFolder, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
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
      case ArchiveKeyState.local:
        icon = Icons.sd_storage_outlined;
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
