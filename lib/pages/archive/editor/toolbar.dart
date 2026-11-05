import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// Owns the editor's selection menu for exactly as long as the editor itself.
///
/// The menu is an entry in the *root* overlay, so it outlives the editor
/// unless something takes it down, and a stale one sits over the rest of the
/// app with its buttons wired to a disposed controller. Hanging it off a
/// widget that lives as long as the `CodeEditor` covers every way out - the
/// route popping, the hex view taking over, a failed reload leaving an error
/// panel in its place - without a call anyone has to remember to add.
class EditorSelectionMenuScope extends StatefulWidget {
  const EditorSelectionMenuScope({super.key, required this.builder});

  final Widget Function(SelectionToolbarController toolbar) builder;

  @override
  State<EditorSelectionMenuScope> createState() =>
      _EditorSelectionMenuScopeState();
}

class _EditorSelectionMenuScopeState extends State<EditorSelectionMenuScope> {
  final EditorSelectionToolbarController _toolbar =
      EditorSelectionToolbarController();

  @override
  void dispose() {
    _toolbar.hide(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_toolbar);
}

/// The editor's cut/copy/paste/select-all menu.
///
/// `re_editor` ships one implementation of `SelectionToolbarController` and it
/// crashes on desktop: its `show` writes `offset: -renderRect!.topLeft`, while
/// the interface declares `Rect? renderRect` and the package's own desktop
/// selection overlay passes null - which a right click is the only thing to
/// reach. The menu threw while the frame was building and left an error widget
/// across the root overlay in its place (Sentry QUNLEASHED-D). So the null
/// branch below is what the package's own signature asks for, not defensive
/// padding to be tidied away. True of `re_editor` 0.10.0, the only release
/// there is; `pubspec.yaml` takes `^0.10.0`.
///
/// Implemented rather than wrapped, because the package's factory hides a
/// private class and its one injection point - `builder` - runs after the
/// offset has been computed. Only the menu is ours: the overlay bookkeeping is
/// Flutter's [ContextMenuController], which the package hand-rolled a copy of.
///
/// With a rect the menu follows the code field's layer, and the offset undoes
/// the follower's origin because the anchors are in global coordinates.
/// Without one there is no origin to undo: the menu goes into the overlay
/// unfollowed, where overlay-local is global for as long as nothing insets the
/// root navigator.
class EditorSelectionToolbarController implements SelectionToolbarController {
  final ContextMenuController _menu = ContextMenuController();

  @override
  void hide(BuildContext context) => _menu.remove();

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final rect = renderRect;
    _menu.show(
      context: context,
      contextMenuBuilder: (_) {
        Widget menu = AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: [
            ContextMenuButtonItem(
              type: ContextMenuButtonType.cut,
              onPressed: () {
                controller.cut();
                hide(context);
              },
            ),
            ContextMenuButtonItem(
              type: ContextMenuButtonType.copy,
              onPressed: () {
                controller.copy();
                hide(context);
              },
            ),
            ContextMenuButtonItem(
              type: ContextMenuButtonType.paste,
              onPressed: () {
                controller.paste();
                hide(context);
              },
            ),
            // The odd one out: the menu stays up, because selecting everything
            // is usually the step before copying it.
            ContextMenuButtonItem(
              type: ContextMenuButtonType.selectAll,
              onPressed: controller.selectAll,
            ),
          ],
        );
        if (rect != null) {
          menu = CompositedTransformFollower(
            link: layerLink,
            showWhenUnlinked: false,
            offset: -rect.topLeft,
            child: menu,
          );
        }
        return _EditorSelectionMenu(visibility: visibility, child: menu);
      },
    );
  }
}

/// Fades the menu in, and keeps a tap on it from unfocusing the editor.
///
/// `re_editor` also wraps its menu in a `Directionality` that re-supplies the
/// value it just inherited, and re-subscribes to `visibility` in
/// `didUpdateWidget`. Neither is kept: the first is a no-op, and the second
/// never fires, because the notifier belongs to the `CodeEditor` and does not
/// change identity under a live menu.
class _EditorSelectionMenu extends StatefulWidget {
  const _EditorSelectionMenu({required this.visibility, required this.child});

  final ValueNotifier<bool> visibility;
  final Widget child;

  @override
  State<_EditorSelectionMenu> createState() => _EditorSelectionMenuState();
}

class _EditorSelectionMenuState extends State<_EditorSelectionMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    duration: SelectionOverlay.fadeDuration,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    // The menu opens at zero opacity, so this is what makes it appear at all.
    _visibilityChanged();
    widget.visibility.addListener(_visibilityChanged);
  }

  @override
  void dispose() {
    widget.visibility.removeListener(_visibilityChanged);
    _fade.dispose();
    super.dispose();
  }

  void _visibilityChanged() {
    if (widget.visibility.value) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => CodeEditorTapRegion(
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}
