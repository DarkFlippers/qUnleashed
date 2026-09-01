import '../../../../../services/localization/l10n.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../theme/colors/display.dart';
import '../../../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../constants.dart';
import '../controller.dart';
import 'editor_widgets.dart';

class EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorAppBar({
    super.key,
    required this.ctrl,
    required this.onClose,
    required this.onSave,
    required this.onExport,
    required this.onImport,
  });

  final PaintController ctrl;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Size get preferredSize => const Size.fromHeight(QPageAppBar.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    return QPageAppBar(
      title: context.l10n.paintTitle,
      leading: IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        QPageAppBarAction(
          onPressed: ctrl.canUndo ? ctrl.undo : null,
          icon: const Icon(Icons.undo),
          tooltip: context.l10n.paintUndo,
        ),
        QPageAppBarAction(
          onPressed: ctrl.canRedo ? ctrl.redo : null,
          icon: const Icon(Icons.redo),
          tooltip: context.l10n.paintRedo,
        ),
        QPageAppBarAction(
          onPressed: onSave,
          icon: const Icon(Icons.save_outlined),
          tooltip: context.l10n.commonSave,
        ),
        PopupMenuButton<int>(
          tooltip: '',
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 0,
              child: MenuLine(
                icon: Icons.download_outlined,
                label: context.l10n.paintImport,
              ),
            ),
            PopupMenuItem(
              value: 1,
              child: MenuLine(
                icon: Icons.upload_outlined,
                label: context.l10n.paintExport,
              ),
            ),
          ],
          onSelected: (v) => v == 0 ? onImport() : onExport(),
        ),
      ],
    );
  }
}

class MenuLine extends StatelessWidget {
  const MenuLine({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.textSecondary),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      ],
    );
  }
}

List<(DrawTool, IconData, String, Matrix4?)> _drawTools(
  BuildContext context,
) => [
  (DrawTool.pencil, Icons.edit_outlined, context.l10n.paintToolPencil, null),
  (DrawTool.fill, Icons.format_color_fill, context.l10n.paintToolFill, null),
  (
    DrawTool.line,
    Icons.remove,
    context.l10n.paintToolLine,
    Matrix4.rotationZ(-math.pi / 4),
  ),
  (DrawTool.rect, Icons.crop_square, context.l10n.paintToolRectangle, null),
  (
    DrawTool.ellipse,
    Icons.radio_button_unchecked,
    context.l10n.paintToolEllipse,
    null,
  ),
];

/// Phone dock: ink and view options on a thin line, drawing tools below it.
class ToolDock extends StatelessWidget {
  const ToolDock({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final display = DisplayColors.forColors(colors);
    final tools = _drawTools(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: [
                InkSwatches(
                  foreground: display.foreground,
                  background: display.background,
                  drawFg: ctrl.drawFg,
                  colors: colors,
                  onPick: ctrl.setDrawFg,
                ),
                const SizedBox(width: 8),
                MiniToolButton(
                  icon: Icons.grid_on,
                  active: ctrl.showGrid,
                  colors: colors,
                  onTap: () => ctrl.setShowGrid(!ctrl.showGrid),
                  tooltip: context.l10n.paintToggleGrid,
                ),
                const Spacer(),
                MiniToolButton(
                  icon: Icons.zoom_out,
                  active: false,
                  colors: colors,
                  onTap: ctrl.zoomOut,
                  tooltip: context.l10n.paintZoomOut,
                ),
                ZoomLabel(ctrl: ctrl, colors: colors),
                MiniToolButton(
                  icon: Icons.zoom_in,
                  active: false,
                  colors: colors,
                  onTap: ctrl.zoomIn,
                  tooltip: context.l10n.paintZoomIn,
                ),
                const SizedBox(width: 6),
                OpsMenu(ctrl: ctrl, colors: colors),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                for (final (tool, icon, label, transform) in tools) ...[
                  Expanded(
                    child: ToolButton(
                      icon: icon,
                      active: ctrl.tool == tool,
                      colors: colors,
                      onTap: () => ctrl.setTool(tool),
                      iconTransform: transform,
                      tooltip: label,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: ToolButton(
                    icon: Icons.layers_outlined,
                    active: ctrl.showOnionSkin,
                    colors: colors,
                    onTap: () => ctrl.setShowOnionSkin(!ctrl.showOnionSkin),
                    tooltip: context.l10n.paintOnionSkin,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop rail: the same controls stacked down the left edge, the way every
/// other pixel editor puts them, so the canvas keeps the middle of the window.
class ToolRail extends StatelessWidget {
  const ToolRail({super.key, required this.ctrl, required this.colors});

  static const double width = 56;

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final display = DisplayColors.forColors(colors);
    final tools = _drawTools(context);

    return Container(
      width: width,
      color: colors.card,
      // A short window must not cut the rail off: it scrolls, by wheel or by
      // dragging it with any pointer, and shows no scrollbar of its own.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          overscroll: false,
          dragDevices: PointerDeviceKind.values.toSet(),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              InkSwatches(
                foreground: display.foreground,
                background: display.background,
                drawFg: ctrl.drawFg,
                colors: colors,
                onPick: ctrl.setDrawFg,
                size: 22,
              ),
              const SizedBox(height: 10),
              for (final (tool, icon, label, transform) in tools)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: SizedBox(
                    height: 38,
                    child: ToolButton(
                      icon: icon,
                      active: ctrl.tool == tool,
                      colors: colors,
                      onTap: () => ctrl.setTool(tool),
                      iconTransform: transform,
                      tooltip: label,
                      background: colors.background,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: SizedBox(
                  height: 38,
                  child: ToolButton(
                    icon: Icons.layers_outlined,
                    active: ctrl.showOnionSkin,
                    colors: colors,
                    onTap: () => ctrl.setShowOnionSkin(!ctrl.showOnionSkin),
                    tooltip: context.l10n.paintOnionSkin,
                    background: colors.background,
                  ),
                ),
              ),
              _Separator(colors: colors),
              MiniToolButton(
                icon: Icons.grid_on,
                active: ctrl.showGrid,
                colors: colors,
                onTap: () => ctrl.setShowGrid(!ctrl.showGrid),
                tooltip: context.l10n.paintToggleGrid,
              ),
              MiniToolButton(
                icon: Icons.zoom_in,
                active: false,
                colors: colors,
                onTap: ctrl.zoomIn,
                tooltip: context.l10n.paintZoomIn,
              ),
              ZoomLabel(ctrl: ctrl, colors: colors),
              MiniToolButton(
                icon: Icons.zoom_out,
                active: false,
                colors: colors,
                onTap: ctrl.zoomOut,
                tooltip: context.l10n.paintZoomOut,
              ),
              _Separator(colors: colors),
              // Desktop has the room, so the frame operations stay visible
              // instead of hiding behind the phone dock's overflow button.
              MiniToolButton(
                icon: Icons.flip,
                active: false,
                colors: colors,
                onTap: ctrl.flipH,
                tooltip: context.l10n.paintFlipHorizontal,
              ),
              MiniToolButton(
                icon: Icons.flip,
                iconTransform: Matrix4.rotationZ(math.pi / 2),
                active: false,
                colors: colors,
                onTap: ctrl.flipV,
                tooltip: context.l10n.paintFlipVertical,
              ),
              MiniToolButton(
                icon: Icons.contrast,
                active: false,
                colors: colors,
                onTap: ctrl.invert,
                tooltip: context.l10n.paintInvert,
              ),
              MiniToolButton(
                icon: Icons.delete_outline,
                active: false,
                colors: colors,
                onTap: ctrl.clearFrame,
                tooltip: context.l10n.commonClear,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.colors});

  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Divider(height: 1, thickness: 1, color: colors.divider),
    );
  }
}

/// Zoom factor; tapping resets it to 100%.
class ZoomLabel extends StatelessWidget {
  const ZoomLabel({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: ctrl.zoomReset,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        height: 26,
        child: Center(
          child: Text(
            ctrl.zoomLabel,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Frame-wide operations: rarely needed mid-stroke, so they live behind one
/// button instead of a row of four.
class OpsMenu extends StatelessWidget {
  const OpsMenu({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: PopupMenuButton<int>(
        tooltip: '',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz, size: 18, color: colors.textSecondary),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 0,
            child: MenuLine(
              icon: Icons.flip,
              label: context.l10n.paintFlipHorizontal,
            ),
          ),
          PopupMenuItem(
            value: 1,
            child: MenuLine(
              icon: Icons.flip,
              label: context.l10n.paintFlipVertical,
            ),
          ),
          PopupMenuItem(
            value: 2,
            child: MenuLine(
              icon: Icons.contrast,
              label: context.l10n.paintInvert,
            ),
          ),
          PopupMenuItem(
            value: 3,
            child: MenuLine(
              icon: Icons.delete_outline,
              label: context.l10n.commonClear,
            ),
          ),
        ],
        onSelected: (v) => switch (v) {
          0 => ctrl.flipH(),
          1 => ctrl.flipV(),
          2 => ctrl.invert(),
          _ => ctrl.clearFrame(),
        },
      ),
    );
  }
}
