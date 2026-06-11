import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../controller.dart';
import '../painters.dart';
import 'editor_widgets.dart';

class FramesSection extends StatelessWidget {
  const FramesSection({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Expanded(child: FramesStrip(ctrl: ctrl, colors: colors)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 14, 6),
                    child: GestureDetector(
                      onTap: ctrl.addFrame,
                      child: Container(
                        width: 40,
                        height: 54,
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.divider, width: 1.5),
                        ),
                        child: Icon(Icons.add, color: colors.textMuted, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final canPlay = ctrl.frames.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      child: Row(
        children: [
          Text(
            'FRAMES · ${ctrl.frames.length}',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: canPlay ? ctrl.togglePlay : null,
            icon: Icon(
              ctrl.isPlaying ? Icons.stop : Icons.play_arrow,
              size: 16,
              color: canPlay ? colors.accent : colors.textMuted,
            ),
            label: Text(
              ctrl.isPlaying ? 'Stop' : 'Play',
              style: TextStyle(
                color: canPlay ? colors.accent : colors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    final canTrigger = ctrl.effectivePassiveCount < ctrl.frames.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: FrameActionButton(
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              colors: colors,
              onTap: ctrl.duplicateFrame,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FrameActionButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              colors: colors,
              onTap: ctrl.deleteFrame,
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: canTrigger ? 1.0 : 0.38,
            child: IgnorePointer(
              ignoring: !canTrigger,
              child: FrameActionButton(
                icon: Icons.touch_app_outlined,
                label: '',
                colors: colors,
                onTap: ctrl.triggerActive,
                accent: true,
              ),
            ),
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
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
                onTap: () => _ctrl.selectFrame(i),
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
    required this.onTap,
  });

  final Uint8List pixels;
  final bool selected;
  final bool isActive;
  final int version;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? colors.accent
        : isActive
            ? colors.accent.withAlpha(80)
            : colors.divider;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 54,
            decoration: BoxDecoration(
              color: colors.screenBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor, width: selected ? 2.0 : 1.0),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                painter: ThumbnailPainter(
                  pixels: pixels,
                  fgColor: colors.screenBorder,
                  bgColor: colors.screenBackground,
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
                    : colors.screenBackground.withAlpha(200),
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
