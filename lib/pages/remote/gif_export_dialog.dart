import 'package:flutter/material.dart';

import '../../theme.dart';

class GifExportOptions {
  const GifExportOptions({required this.scale, required this.speed});

  final int scale;
  final int speed;
}

Future<GifExportOptions?> showGifExportDialog(BuildContext context) {
  var selectedScale = 2;
  var selectedSpeed = 1;

  return showDialog<GifExportOptions>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.appColors;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          Widget chip({
            required int value,
            required int selected,
            required ValueChanged<int> onSelected,
          }) {
            final active = selected == value;
            return ChoiceChip(
              label: Text('${value}x'),
              selected: active,
              onSelected: (_) => setDialogState(() => onSelected(value)),
              selectedColor: colors.accent.withValues(alpha: 0.18),
              labelStyle: TextStyle(
                color: active ? colors.accent : colors.textPrimary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: active ? colors.accent : colors.divider,
              ),
            );
          }

          Widget section(String title, int selected, ValueChanged<int> onSelected) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in const [1, 2, 4])
                      chip(value: v, selected: selected, onSelected: onSelected),
                  ],
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Export GIF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section('Scale', selectedScale, (v) => selectedScale = v),
                const SizedBox(height: 18),
                section('Speed', selectedSpeed, (v) => selectedSpeed = v),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  GifExportOptions(scale: selectedScale, speed: selectedSpeed),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}
