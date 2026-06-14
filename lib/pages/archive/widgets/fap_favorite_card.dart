import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../components/icon.dart';
import '../../../theme.dart';
import '../fap_icon.dart';
import '../models/fap_favorite.dart';

/// Favorites-list card for an on-device app (`.fap`). Renders the icon
/// extracted from the app binary when available, falling back to the default
/// app glyph otherwise.
class FapFavoriteCard extends StatelessWidget {
  const FapFavoriteCard({
    super.key,
    required this.favorite,
    required this.onTap,
    required this.onRemove,
  });

  final FapFavorite favorite;

  /// Launches the app on the device and opens the remote control.
  final VoidCallback onTap;

  /// Unstars the app (removes it from favorites).
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icon = favorite.icon;
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
              if (icon != null)
                _FapIconBadge(icon: icon, color: colors.accent)
              else
                QIconBadge(
                  asset: 'assets/ic/app/apps.svg',
                  color: colors.accent,
                  iconSize: 22,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      favorite.subFolder.isEmpty ? 'Apps' : favorite.subFolder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StarButton(onTap: onRemove),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({required this.onTap});

  final VoidCallback onTap;

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
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade600),
      ),
    );
  }
}

class _FapIconBadge extends StatelessWidget {
  const _FapIconBadge({required this.icon, required this.color});

  final Uint8List icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        size: const Size.square(22),
        painter: _FapIconPainter(icon: icon, color: color),
      ),
    );
  }
}

class _FapIconPainter extends CustomPainter {
  _FapIconPainter({required this.icon, required this.color});

  final Uint8List icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rowBytes = (fapIconWidth + 7) >> 3;
    final cell = size.width / fapIconWidth;
    final paint = Paint()..color = color;
    for (var y = 0; y < fapIconHeight; y++) {
      for (var x = 0; x < fapIconWidth; x++) {
        final byteIdx = y * rowBytes + (x >> 3);
        if (byteIdx >= icon.length) continue;
        if ((icon[byteIdx] & (1 << (x & 7))) == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FapIconPainter old) =>
      old.icon != icon || old.color != color;
}
