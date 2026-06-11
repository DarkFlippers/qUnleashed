import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../constants.dart';
import '../controller.dart';
import 'editor_widgets.dart';

class EditorAppBar extends StatelessWidget {
  const EditorAppBar({
    super.key,
    required this.ctrl,
    required this.colors,
    required this.topInset,
    required this.onClose,
    required this.onExport,
  });

  final PaintController ctrl;
  final QAppColors colors;
  final double topInset;
  final VoidCallback onClose;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.accent,
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.arrow_back, color: colors.onAccent),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pixel Draw',
                    style: TextStyle(
                      color: colors.onAccent,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    '128 × 64 · monochrome',
                    style: TextStyle(
                      color: colors.onAccent.withAlpha(180),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: ctrl.canUndo ? ctrl.undo : null,
              icon: Icon(Icons.undo, color: colors.onAccent),
              tooltip: 'Undo',
            ),
            IconButton(
              onPressed: ctrl.canRedo ? ctrl.redo : null,
              icon: Icon(Icons.redo, color: colors.onAccent),
              tooltip: 'Redo',
            ),
            IconButton(
              onPressed: onExport,
              icon: Icon(Icons.save_outlined, color: colors.onAccent),
              tooltip: 'Save',
            ),
          ],
        ),
      ),
    );
  }
}

class ColorAndZoomRow extends StatelessWidget {
  const ColorAndZoomRow({super.key, required this.ctrl, required this.colors});

  final PaintController ctrl;
  final QAppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          PaintColorSwatch(
            color: colors.screenBorder,
            selected: ctrl.drawFg,
            onTap: () => ctrl.setDrawFg(true),
          ),
          const SizedBox(width: 6),
          PaintColorSwatch(
            color: colors.screenBackground,
            selected: !ctrl.drawFg,
            onTap: () => ctrl.setDrawFg(false),
          ),
          const Spacer(),
          IconToolButton(
            icon: Icons.grid_on,
            active: ctrl.showGrid,
            colors: colors,
            onTap: () => ctrl.setShowGrid(!ctrl.showGrid),
            tooltip: 'Toggle grid',
          ),
          const SizedBox(width: 4),
          IconToolButton(
            icon: Icons.zoom_out,
            active: false,
            colors: colors,
            onTap: ctrl.zoomOut,
            tooltip: 'Zoom out',
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
            tooltip: 'Zoom in',
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
      (DrawTool.pencil, Icons.edit_outlined, 'Pencil', null as Matrix4?),
      (DrawTool.fill, Icons.format_color_fill, 'Fill', null),
      (DrawTool.line, Icons.remove, 'Line', Matrix4.rotationZ(-math.pi / 4)),
      (DrawTool.rect, Icons.crop_square, 'Rectangle', null),
      (DrawTool.ellipse, Icons.radio_button_unchecked, 'Ellipse', null),
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
              tooltip: 'Onion skin',
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
              tooltip: 'Flip horizontal',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OpsButton(
              icon: Icons.flip,
              iconTransform: Matrix4.rotationZ(math.pi / 2),
              colors: colors,
              onTap: ctrl.flipV,
              tooltip: 'Flip vertical',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OpsButton(
              icon: Icons.contrast,
              colors: colors,
              onTap: ctrl.invert,
              tooltip: 'Invert',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OpsButton(
              icon: Icons.delete_outline,
              colors: colors,
              onTap: ctrl.clearFrame,
              tooltip: 'Clear',
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
              label: 'Export',
              colors: colors,
              onTap: onExport,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ExportButton(
              icon: Icons.download_outlined,
              label: 'Import',
              colors: colors,
              onTap: onImport,
            ),
          ),
        ],
      ),
    );
  }
}
