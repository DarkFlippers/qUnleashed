import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../style.dart';
import 'document.dart';

/// On-screen hex pad, so bytes can be typed on a device without a keyboard.
class HexKeypad extends StatelessWidget {
  const HexKeypad({super.key, required this.document, required this.onClose});

  final HexDocument document;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: document,
      builder: (context, _) {
        final insert = document.mode == HexEditMode.insert;
        return Container(
          decoration: BoxDecoration(
            color: colors.card,
            border: Border(top: BorderSide(color: colors.divider, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (var value = 0; value < 8; value++) _digit(colors, value),
                  _action(
                    colors,
                    icon: Icons.keyboard_arrow_left_rounded,
                    tooltip: l10n.hexMoveLeft,
                    onPressed: () => document.moveNibble(-1),
                  ),
                  _action(
                    colors,
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: l10n.hexMoveUp,
                    onPressed: () => document.moveBy(-16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var value = 8; value < 16; value++)
                    _digit(colors, value),
                  _action(
                    colors,
                    icon: Icons.keyboard_arrow_right_rounded,
                    tooltip: l10n.hexMoveRight,
                    onPressed: () => document.moveNibble(1),
                  ),
                  _action(
                    colors,
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: l10n.hexMoveDown,
                    onPressed: () => document.moveBy(16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _action(
                    colors,
                    icon: Icons.backspace_outlined,
                    tooltip: l10n.hexBackspace,
                    onPressed: document.backspace,
                  ),
                  _action(
                    colors,
                    icon: Icons.delete_outline_rounded,
                    tooltip: l10n.hexDeleteByte,
                    onPressed: document.deleteForward,
                  ),
                  _action(
                    colors,
                    icon: insert
                        ? Icons.text_rotation_none_rounded
                        : Icons.edit_rounded,
                    tooltip: insert
                        ? l10n.hexInsertMode
                        : l10n.hexOverwriteMode,
                    selected: insert,
                    onPressed: () => document.mode = insert
                        ? HexEditMode.overwrite
                        : HexEditMode.insert,
                  ),
                  _action(
                    colors,
                    icon: Icons.undo_rounded,
                    tooltip: l10n.hexUndo,
                    onPressed: document.canUndo ? document.undo : null,
                  ),
                  _action(
                    colors,
                    icon: Icons.redo_rounded,
                    tooltip: l10n.hexRedo,
                    onPressed: document.canRedo ? document.redo : null,
                  ),
                  _action(
                    colors,
                    icon: Icons.keyboard_hide_rounded,
                    tooltip: l10n.commonClose,
                    onPressed: onClose,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _digit(QAppColors colors, int value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () {
            document.pane = HexPane.hex;
            document.inputNibble(value);
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: colors.background,
            ),
            child: Text(
              value.toRadixString(16).toUpperCase(),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontFamily: kEditorFontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(
    QAppColors colors, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: selected ? colors.accent : colors.background,
              ),
              child: Icon(
                icon,
                size: 18,
                color: onPressed == null
                    ? colors.textMuted
                    : selected
                    ? colors.onAccent
                    : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
