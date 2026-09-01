import '../../../../../services/localization/l10n.dart';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../theme/colors/display.dart';
import '../../../../../theme/theme.dart';
import '../controller.dart';
import '../painters.dart';
import 'editor_toolbars.dart';

/// Thumbnail (and side button) height; the strip is exactly this tall.
const double _thumbHeight = 54;

/// The frame timeline: play/stop, the reorderable strip itself, and the button
/// that appends a frame. Per-frame actions live in the menu a second tap on the
/// selected frame opens, so the strip stays one line tall.
class FramesSection extends StatelessWidget {
  const FramesSection({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final canPlay = ctrl.frames.length > 1;
    // Everything on this row is exactly _thumbHeight tall and centred, so the
    // buttons and the thumbnails sit on one line.
    return SizedBox(
      height: _thumbHeight + 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 12),
          _SideButton(
            icon: ctrl.isPlaying ? Icons.stop : Icons.play_arrow,
            colors: colors,
            enabled: canPlay,
            onTap: ctrl.togglePlay,
            tooltip: ctrl.isPlaying
                ? context.l10n.paintStop
                : context.l10n.paintPlay,
          ),
          Expanded(
            child: SizedBox(
              height: _thumbHeight,
              child: _FadedEdges(
                child: FramesStrip(ctrl: ctrl, colors: colors),
              ),
            ),
          ),
          _SideButton(
            icon: Icons.add,
            colors: colors,
            onTap: ctrl.addFrame,
            tooltip: null,
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Both ends of the timeline carry the same button, so the strip reads as
/// one row instead of two mismatched controls squeezing the thumbnails.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.colors,
    required this.onTap,
    required this.tooltip,
    this.enabled = true,
  });

  final IconData icon;
  final QAppColors colors;
  final VoidCallback onTap;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: _thumbHeight,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.divider),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? colors.textSecondary
              : colors.textMuted.withAlpha(110),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Fades the thumbnails out at both ends instead of slicing one in half at the
/// edge of the viewport.
class _FadedEdges extends StatelessWidget {
  const _FadedEdges({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = (14 / rect.width).clamp(0.0, 0.4);
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, fade, 1 - fade, 1],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

/// Frame actions for the desktop settings column, where there is room to show
/// them outright instead of behind the timeline's tap-again menu.
class FrameActions extends StatelessWidget {
  const FrameActions({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.copy_outlined,
              label: context.l10n.paintDuplicate,
              colors: colors,
              onTap: ctrl.duplicateFrame,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              icon: Icons.delete_outline,
              label: context.l10n.commonDelete,
              colors: colors,
              color: colors.danger,
              onTap: ctrl.deleteFrame,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final QAppColors colors;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? colors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal, reorderable strip of frame thumbnails.
///
/// Interaction model:
///  * A quick horizontal **swipe scrolls** the history.
///  * **Long-pressing** a thumbnail grabs it — it lifts and follows the finger
///    until released, at which point it is dropped at the new position.
///  * Dragging a grabbed frame toward either **edge auto-scrolls** the history
///    so you can reorder past the visible range (handled by the underlying
///    [ReorderableListView]'s edge auto-scroller).
///  * Tapping the **already selected** frame opens its actions.
class FramesStrip extends StatefulWidget {
  const FramesStrip({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  State<FramesStrip> createState() => _FramesStripState();
}

class _FramesStripState extends State<FramesStrip> {
  // 96px thumbnail + 8px trailing gap.
  static const double _itemExtent = 104.0;

  final ScrollController _scroll = ScrollController();
  int _lastFrame = -1;
  bool _dragging = false;

  PaintController get _ctrl => widget.ctrl;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keep the active frame visible whenever selection changes from elsewhere
  /// (drawing on a frame, play/stop, trigger, add/duplicate, …). Skipped while
  /// the user is mid-drag so we don't fight the edge auto-scroller.
  void _ensureSelectedVisible() {
    final i = _ctrl.currentFrame;
    if (i == _lastFrame) return;
    _lastFrame = i;
    if (_dragging) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final itemStart = i * _itemExtent;
      final itemEnd = itemStart + _itemExtent;
      final viewport = pos.viewportDimension;
      double? target;
      if (itemStart < pos.pixels) {
        target = itemStart;
      } else if (itemEnd > pos.pixels + viewport) {
        target = itemEnd - viewport;
      }
      if (target == null) return;
      _scroll.animateTo(
        target.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _onTap(int index, Offset globalPosition) async {
    if (index != _ctrl.currentFrame) {
      _ctrl.selectFrame(index);
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 0,
          child: MenuLine(
            icon: Icons.copy_outlined,
            label: l10n.paintDuplicate,
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: MenuLine(icon: Icons.delete_outline, label: l10n.commonDelete),
        ),
      ],
    );
    if (choice == 0) _ctrl.duplicateFrame();
    if (choice == 1) _ctrl.deleteFrame();
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectedVisible();
    final colors = widget.colors;
    // Enable drag-to-scroll for every pointer kind. By default Flutter only
    // lets touch/stylus drag a scrollable, so on desktop a mouse/trackpad swipe
    // over the strip would do nothing — here it should always scroll the
    // history (long-press still grabs a frame for reordering).
    return ScrollConfiguration(
      behavior: const _DragScrollBehavior(),
      child: ReorderableListView.builder(
        scrollController: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        buildDefaultDragHandles: false,
        itemExtent: _itemExtent,
        itemCount: _ctrl.frames.length,
        onReorderStart: (_) => _dragging = true,
        onReorderEnd: (_) => _dragging = false,
        onReorderItem: _ctrl.reorderFrame,
        proxyDecorator: (child, index, animation) {
          // Lift the grabbed frame so it visibly "sticks" to the finger.
          return Material(
            color: Colors.transparent,
            elevation: 8,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(6),
            child: child,
          );
        },
        itemBuilder: (context, i) {
          return ReorderableDelayedDragStartListener(
            key: ValueKey(i),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FrameThumbnail(
                pixels: _ctrl.frames[i],
                selected: i == _ctrl.currentFrame,
                isActive: i >= _ctrl.effectivePassiveCount,
                version: _ctrl.pixelVersion,
                colors: colors,
                onTapAt: (pos) => _onTap(i, pos),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// [ScrollBehavior] that allows dragging to scroll with any pointer device
/// (touch, mouse, trackpad, stylus), not just touch/stylus.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

class _FrameThumbnail extends StatelessWidget {
  const _FrameThumbnail({
    required this.pixels,
    required this.selected,
    required this.isActive,
    required this.version,
    required this.colors,
    required this.onTapAt,
  });

  final Uint8List pixels;
  final bool selected;
  final bool isActive;
  final int version;
  final QAppColors colors;
  final ValueChanged<Offset> onTapAt;

  @override
  Widget build(BuildContext context) {
    final display = DisplayColors.forColors(colors);
    final borderColor = selected
        ? colors.accent
        : isActive
        ? colors.accent.withAlpha(80)
        : colors.divider;
    return GestureDetector(
      onTapUp: (d) => onTapAt(d.globalPosition),
      child: Stack(
        children: [
          Container(
            width: 96,
            height: _thumbHeight,
            decoration: BoxDecoration(
              color: display.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: borderColor,
                width: selected ? 2.0 : 1.0,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                painter: ThumbnailPainter(
                  pixels: pixels,
                  fgColor: display.foreground,
                  bgColor: display.background,
                  version: version,
                ),
              ),
            ),
          ),
          Positioned(
            top: 3,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isActive
                    ? colors.accent.withAlpha(200)
                    : display.background.withAlpha(200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isActive ? 'A' : 'P',
                style: TextStyle(
                  color: isActive ? colors.onAccent : colors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
