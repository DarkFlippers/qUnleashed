import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/colors/display.dart';
import '../../../theme/theme.dart';
import 'project.dart';

/// Lazily decodes and loops a project's preview frames. Decoding happens once
/// the row is built (scrolled into view), keeping large libraries cheap.
class ProjectPreview extends StatefulWidget {
  const ProjectPreview({
    super.key,
    required this.project,
    this.width,
    required this.full,
    required this.colors,
    this.highlight = false,
    this.showBorder = true,
    this.radius = 6,
  });

  final PaintProject project;

  /// Fixed width; null lets the preview fill its box at 2:1.
  final double? width;
  final bool full;
  final QAppColors colors;
  final bool highlight;

  /// Off inside a card that already frames the preview itself.
  final bool showBorder;
  final double radius;

  @override
  State<ProjectPreview> createState() => _ProjectPreviewState();
}

class _ProjectPreviewState extends State<ProjectPreview> {
  List<ui.Image> _frames = const [];
  Timer? _timer;
  int _cursor = 0;
  bool _loading = true;

  double? get _w => widget.width;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preview = await widget.project.loadPreview(full: widget.full);
    if (!mounted) {
      _disposeFrames(preview.frames);
      return;
    }
    setState(() {
      _frames = preview.frames;
      _loading = false;
    });
    if (preview.frames.length > 1) {
      _timer = Timer.periodic(
        Duration(milliseconds: preview.delayMs.clamp(33, 2000)),
        (_) {
          if (!mounted) return;
          setState(() => _cursor = (_cursor + 1) % _frames.length);
        },
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposeFrames(_frames);
    super.dispose();
  }

  /// A frame order may reference the same [ui.Image] more than once (e.g.
  /// "0 1 2 1 0"), so dispose each unique image only once to avoid a
  /// double-dispose assertion.
  static void _disposeFrames(List<ui.Image> frames) {
    final seen = <ui.Image>{};
    for (final img in frames) {
      if (seen.add(img)) img.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // The outline is drawn *over* the frame, so the image can never clip it and
    // its width can change on selection without resizing anything.
    final content = Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: ColoredBox(
            color: DisplayColors.forColors(colors).background,
            child: Center(child: _buildFrame(colors)),
          ),
        ),
        if (widget.showBorder)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: widget.highlight
                      ? colors.accent
                      : colors.screenBorder.withAlpha(40),
                  width: widget.highlight ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );

    final w = _w;
    if (w == null) return AspectRatio(aspectRatio: 2, child: content);
    return SizedBox(width: w, height: w / 2, child: content);
  }

  Widget _buildFrame(QAppColors colors) {
    if (_loading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
      );
    }
    if (_frames.isEmpty) {
      return Icon(
        Icons.broken_image_outlined,
        size: 18,
        color: colors.textMuted,
      );
    }
    return SizedBox.expand(
      child: RawImage(
        image: _frames[_cursor % _frames.length],
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none,
      ),
    );
  }
}
