import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// Cut/copy/paste menu shown on a long press or a right click inside the editor.
final SelectionToolbarController editorSelectionToolbar =
    MobileSelectionToolbarController(
      builder:
          ({
            required BuildContext context,
            required TextSelectionToolbarAnchors anchors,
            required CodeLineEditingController controller,
            required VoidCallback onDismiss,
            required VoidCallback onRefresh,
          }) {
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: anchors,
              buttonItems: [
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.cut,
                  onPressed: () {
                    controller.cut();
                    onDismiss();
                  },
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.copy,
                  onPressed: () {
                    controller.copy();
                    onDismiss();
                  },
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.paste,
                  onPressed: () {
                    controller.paste();
                    onDismiss();
                  },
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.selectAll,
                  onPressed: () {
                    controller.selectAll();
                    onRefresh();
                  },
                ),
              ],
            );
          },
    );
