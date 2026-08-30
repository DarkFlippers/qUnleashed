import '../../../../../services/localization/l10n.dart';
import 'dart:math' as math;

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
    required this.onExport,
  });

  final PaintController ctrl;
  final VoidCallback onClose;
  final VoidCallback onExport;

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
          onPressed: onExport,
          icon: const Icon(Icons.save_outlined),
          tooltip: context.l10n.commonSave,
        ),
      ],
    );
  }
}

class ColorAndZoomRow extends StatelessWidget {
  const ColorAndZoomRow({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final display = DisplayColors.forColors(colors);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          PaintColorSwatch(
            color: display.foreground,
            selected: ctrl.drawFg,
            onTap: () => ctrl.setDrawFg(true),
          ),
          const SizedBox(width: 6),
          PaintColorSwatch(
            color: display.background,
            selected: !ctrl.drawFg,
            onTap: () => ctrl.setDrawFg(false),
          ),
          const Spacer(),
          IconToolButton(
            icon: Icons.grid_on,
            active: ctrl.showGrid,
            colors: colors,
            onTap: () => ctrl.setShowGrid(!ctrl.showGrid),
            tooltip: context.l10n.paintToggleGrid,
          ),
          const SizedBox(width: 4),
          IconToolButton(
            icon: Icons.zoom_out,
            active: false,
            colors: colors,
            onTap: ctrl.zoomOut,
            tooltip: context.l10n.paintZoomOut,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: ctrl.zoomReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ctrl.zoomLabel,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconToolButton(
            icon: Icons.zoom_in,
            active: false,
            colors: colors,
            onTap: ctrl.zoomIn,
            tooltip: context.l10n.paintZoomIn,
          ),
        ],
      ),
    );
  }
}

class ToolRow extends StatelessWidget {
  const ToolRow({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    final drawTools = [
      (DrawTool.pencil, Icons.edit_outlined, context.l10n.paintToolPencil, null as Matrix4?),
      (DrawTool.fill, Icons.format_color_fill, context.l10n.paintToolFill, null),
      (DrawTool.line, Icons.remove, context.l10n.paintToolLine, Matrix4.rotationZ(-math.pi / 4)),
      (DrawTool.rect, Icons.crop_square, context.l10n.paintToolRectangle, null),
      (DrawTool.ellipse, Icons.radio_button_unchecked, context.l10n.paintToolEllipse, null),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (int i = 0; i < drawTools.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: ToolButton(
                icon: drawTools[i].$2,
                active: ctrl.tool == drawTools[i].$1,
                colors: colors,
                onTap: () => ctrl.setTool(drawTools[i].$1),
                iconTransform: drawTools[i].$4,
                tooltip: drawTools[i].$3,
              ),
            ),
          ],
          const SizedBox(width: 6),
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
    );
  }
}

class OpsRow extends StatelessWidget {
  const OpsRow({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: OpsButton(
              icon: Icons.flip,
              colors: colors,
              onTap: ctrl.flipH,
              tooltip: context.l10n.paintFlipHorizontal,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OpsButton(
              icon: Icons.flip,
              iconTransform: Matrix4.rotationZ(math.pi / 2),
              colors: colors,
              onTap: ctrl.flipV,
              tooltip: context.l10n.paintFlipVertical,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OpsButton(
              icon: Icons.contrast,
              colors: colors,
              onTap: ctrl.invert,
              tooltip: context.l10n.paintInvert,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OpsButton(
              icon: Icons.delete_outline,
              colors: colors,
              onTap: ctrl.clearFrame,
              tooltip: context.l10n.commonClear,
            ),
          ),
        ],
      ),
    );
  }
}

class ExportRow extends StatelessWidget {
  const ExportRow({
    super.key,
    required this.colors,
    required this.onExport,
    required this.onImport,
  });

  final QAppColors colors;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: ExportButton(
              icon: Icons.upload_outlined,
              label: context.l10n.paintExport,
              colors: colors,
              onTap: onExport,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ExportButton(
              icon: Icons.download_outlined,
              label: context.l10n.paintImport,
              colors: colors,
              onTap: onImport,
            ),
          ),
        ],
      ),
    );
  }
}
