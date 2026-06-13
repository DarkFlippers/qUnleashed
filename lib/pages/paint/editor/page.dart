import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/repository/app.dart';
import '../../../theme.dart';
import '../../../widgets/notification.dart';
import '../../remote/gif_encoder.dart';
import '../codec.dart';
import '../constants.dart';
import '../dolphin_animation.dart';
import '../project.dart';
import 'controller.dart';
import 'widgets/animation_panel.dart';
import 'widgets/canvas_view.dart';
import 'widgets/editor_toolbars.dart';
import 'widgets/editor_widgets.dart';
import 'widgets/frames_strip.dart';

class PaintPage extends StatefulWidget {
  const PaintPage({super.key, this.project});

  /// Project to load into the canvas when the editor opens. When null the editor
  /// starts a fresh, blank project (which becomes a draft once edited).
  final PaintProject? project;

  @override
  State<PaintPage> createState() => _PaintPageState();
}

class _PaintPageState extends State<PaintPage> {
  late final PaintController _ctrl;

  // Draft autosave: the working frames are persisted to a `.drafts` folder so
  // the project manager can surface unsaved work. [_baselineVersion] marks the
  // controller's pixelVersion at which the canvas is considered "clean".
  String? _draftId;
  String? _draftDir;
  int _baselineVersion = 0;
  Timer? _autosaveTimer;
  bool _savingDraft = false;

  @override
  void initState() {
    super.initState();
    _ctrl = PaintController();
    _ctrl.addListener(_onControllerChange);
    final project = widget.project;
    if (project != null && project.isDraft &&
        project.type == PaintProjectType.dolphin) {
      // Editing an existing draft → keep writing to the same folder.
      _draftId = project.id;
      _draftDir = project.path;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (project != null) {
        await _loadProject(project);
      }
      // Whatever we loaded (or the empty start) is the clean baseline.
      _baselineVersion = _ctrl.pixelVersion;
      // Stream the opening canvas; the session buffers it until the display has
      // started, so the first frame reliably reaches a connected device.
      _ctrl.schedulePush();
    });
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
    _scheduleAutosave();
  }

  Future<void> _loadProject(PaintProject project) async {
    try {
      switch (project.type) {
        case PaintProjectType.dolphin:
          final meta = project.metaPath;
          if (meta != null) await _importDolphinFromPath(meta);
        case PaintProjectType.gif:
          await _importGif(await io.File(project.path).readAsBytes());
        case PaintProjectType.drawing:
          final pix = await decodePngToPixels(
            await io.File(project.path).readAsBytes(),
          );
          _ctrl.importFramesFromPixels([pix], pfc: 1);
      }
    } catch (e) {
      if (!mounted) return;
      context.showNotification('Open failed: $e', type: QNotificationType.error);
    }
  }

  void _scheduleAutosave() {
    if (_ctrl.pixelVersion == _baselineVersion) return; // not dirty
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1200), _autosaveDraft);
  }

  Future<void> _autosaveDraft() async {
    if (_savingDraft) return;
    if (_ctrl.pixelVersion == _baselineVersion) return;
    _savingDraft = true;
    try {
      _draftId ??= PaintDraftStore.newDraftId();
      _draftDir ??= await PaintDraftStore.dirPathForDraft(_draftId!);
      await writeDolphinFolder(
        io.Directory(_draftDir!),
        frames: _ctrl.frames.map((f) => Uint8List.fromList(f)).toList(),
        passiveFrames: _ctrl.effectivePassiveCount,
        frameRate: _ctrl.frameRate,
        duration: _ctrl.duration,
        activeCycles: _ctrl.activeCycles,
        activeCooldown: _ctrl.activeCooldown,
        compress: _ctrl.compressBm,
      );
    } catch (e) {
      debugPrint('[PaintEditor] autosave draft failed: $e');
    } finally {
      _savingDraft = false;
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _ctrl.removeListener(_onControllerChange);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_ctrl.isClosing) return;
    _autosaveTimer?.cancel();
    await _autosaveDraft(); // persist the latest edits as a draft before leaving
    _ctrl.close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _exportPng() async {
    try {
      final png = await PaintCodec.frameToPng(_ctrl.frames[_ctrl.currentFrame]);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dir = await appDrawingsDirectory();
      final file = io.File(pathJoin([dir.path, 'drawing_$ts.png']));
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      context.showNotification('Saved: ${file.path}', type: QNotificationType.good);
    } catch (e) {
      if (!mounted) return;
      context.showNotification('Export PNG failed: $e', type: QNotificationType.error);
    }
  }

  Future<void> _exportGif() async {
    try {
      final delays = List.filled(_ctrl.frames.length, kAnimFrameDelay);
      final gif = FlipperGifEncoder.encode(
        width: kCanvasWidth,
        height: kCanvasHeight,
        frames: _ctrl.frames.map((f) => Uint8List.fromList(f)).toList(),
        delaysMs: delays,
        color0: const Color(0xFFDFDFDF).toARGB32(),
        color1: const Color(0xFF000000).toARGB32(),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dir = await appAnimationsDirectory();
      final file = io.File(pathJoin([dir.path, 'animation_$ts.gif']));
      await file.writeAsBytes(gif, flush: true);
      if (!mounted) return;
      context.showNotification('Saved: ${file.path}', type: QNotificationType.good);
    } catch (e) {
      if (!mounted) return;
      context.showNotification('Export GIF failed: $e', type: QNotificationType.error);
    }
  }

  Future<void> _onExport() async {
    if (_ctrl.frames.length > 1) {
      await _exportGif();
    } else {
      await _exportPng();
    }
  }

  Future<void> _exportDolphin() async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final animName = 'anim_${ts}_128x64';
      final baseDir = await appAnimationsDirectory();
      final animDir = io.Directory(pathJoin([baseDir.path, animName]));

      await writeDolphinFolder(
        animDir,
        frames: _ctrl.frames.map((f) => Uint8List.fromList(f)).toList(),
        passiveFrames: _ctrl.effectivePassiveCount,
        frameRate: _ctrl.frameRate,
        duration: _ctrl.duration,
        activeCycles: _ctrl.activeCycles,
        activeCooldown: _ctrl.activeCooldown,
        compress: _ctrl.compressBm,
      );

      if (!mounted) return;
      context.showNotification('Dolphin saved: ${animDir.path}', type: QNotificationType.good);
    } catch (e) {
      if (!mounted) return;
      context.showNotification('Export Dolphin failed: $e', type: QNotificationType.error);
    }
  }

  Future<void> _showExportDialog() async {
    if (!mounted) return;
    final colors = context.appColors;
    final n = _ctrl.frames.length;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Export',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AlertTile(
              icon: Icons.folder_zip_outlined,
              title: 'Dolphin Animation',
              subtitle: '$n frame${n == 1 ? '' : 's'} · meta.txt + .bm files',
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                _exportDolphin();
              },
            ),
            if (n > 1)
              AlertTile(
                icon: Icons.gif_box_outlined,
                title: 'GIF Animation',
                subtitle: '$n frames',
                colors: colors,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportGif();
                },
              ),
            AlertTile(
              icon: Icons.image_outlined,
              title: 'PNG Image',
              subtitle: 'Current frame only',
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                _exportPng();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _onImport() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final name = file.name.toLowerCase();
      final ext = file.extension?.toLowerCase() ?? '';
      final bytes = file.bytes;
      final path = file.path;

      if (name == 'meta.txt') {
        if (path != null) {
          await _importDolphinFromPath(path);
        } else {
          if (!mounted) return;
          context.showNotification('File path unavailable', type: QNotificationType.error);
        }
        return;
      }

      if (ext == 'bm') {
        final data = bytes ?? (path != null ? await io.File(path).readAsBytes() : null);
        if (data != null) await _importBmSingle(data);
        return;
      }

      if (bytes == null) return;

      if (ext == 'gif') {
        await _importGif(bytes);
      } else if (ext == 'png') {
        await _importPng(bytes);
      } else {
        if (!mounted) return;
        context.showNotification('Unsupported file type', type: QNotificationType.error);
      }
    } catch (e) {
      if (!mounted) return;
      context.showNotification('Import failed: $e', type: QNotificationType.error);
    }
  }

  Future<void> _importPng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: kCanvasWidth,
      targetHeight: kCanvasHeight,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (bd == null) return;

    final pix = Uint8List(kCanvasWidth * kCanvasHeight);
    PaintCodec.rgbaToPixels(bd.buffer.asUint8List(), pix);
    _ctrl.importSinglePixelFrame(pix);

    if (!mounted) return;
    context.showNotification('PNG imported', type: QNotificationType.good);
  }

  Future<void> _importGif(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: kCanvasWidth,
      targetHeight: kCanvasHeight,
    );
    final count = codec.frameCount;
    if (count == 0) return;

    final newFrames = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      final f = await codec.getNextFrame();
      final img = f.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (bd == null) continue;
      final pix = Uint8List(kCanvasWidth * kCanvasHeight);
      PaintCodec.rgbaToPixels(bd.buffer.asUint8List(), pix);
      newFrames.add(pix);
    }
    if (newFrames.isEmpty) return;

    _ctrl.importFramesFromPixels(newFrames);
    if (!mounted) return;
    context.showNotification(
      'GIF imported: ${newFrames.length} frame(s)',
      type: QNotificationType.good,
    );
  }

  Future<void> _importDolphinFromPath(String path) async {
    try {
      final metaFile = io.File(path);
      final animDir = metaFile.parent;
      final metaText = await metaFile.readAsString();

      final passiveFrames = PaintCodec.parseDolphinInt(metaText, 'Passive frames') ?? 0;
      final activeFrames = PaintCodec.parseDolphinInt(metaText, 'Active frames') ?? 0;

      // Frame dimensions can be smaller than our fixed canvas (e.g. 128×54).
      final width = PaintCodec.parseDolphinInt(metaText, 'Width') ?? kCanvasWidth;
      final height = PaintCodec.parseDolphinInt(metaText, 'Height') ?? kCanvasHeight;
      final expectedBytes = ((width + 7) >> 3) * height;

      final orderMatch =
          RegExp(r'^Frames order: (.+)$', multiLine: true).firstMatch(metaText);
      final orderStr = orderMatch?.group(1)?.trim() ?? '';

      int maxFrameIdx = (passiveFrames + activeFrames - 1).clamp(0, 255);
      if (orderStr.isNotEmpty) {
        for (final s in orderStr.split(RegExp(r'\s+'))) {
          final n = int.tryParse(s);
          if (n != null && n > maxFrameIdx) maxFrameIdx = n;
        }
      }

      final newFrames = <Uint8List>[];
      for (int i = 0; i <= maxFrameIdx; i++) {
        final bmFile = io.File(pathJoin([animDir.path, 'frame_$i.bm']));
        if (!await bmFile.exists()) {
          if (newFrames.isNotEmpty) break;
          continue;
        }
        final bmData = await bmFile.readAsBytes();
        final xbm = PaintCodec.decodeBmFile(bmData);
        if (xbm == null || xbm.length < expectedBytes) continue;
        newFrames.add(PaintCodec.xbmToPixels(xbm, srcWidth: width, srcHeight: height));
      }

      if (newFrames.isEmpty) {
        if (!mounted) return;
        context.showNotification('No valid frames found', type: QNotificationType.error);
        return;
      }

      _ctrl.importFramesFromPixels(
        newFrames,
        fr: PaintCodec.parseDolphinInt(metaText, 'Frame rate') ?? 2,
        dur: PaintCodec.parseDolphinInt(metaText, 'Duration') ?? 3600,
        ac: PaintCodec.parseDolphinInt(metaText, 'Active cycles') ?? 1,
        acd: PaintCodec.parseDolphinInt(metaText, 'Active cooldown') ?? 7,
        pfc: passiveFrames,
      );

      if (!mounted) return;
      context.showNotification(
        'Dolphin: ${newFrames.length} frames imported',
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification('Import Dolphin failed: $e', type: QNotificationType.error);
    }
  }

  Future<void> _importBmSingle(Uint8List data) async {
    final xbm = PaintCodec.decodeBmFile(data);
    // Flipper bitmaps are 128px wide (16 bytes/row); infer the height from the
    // decoded size so non-64px-tall frames (e.g. 128×54) still import.
    const rowBytes = kCanvasWidth ~/ 8;
    if (xbm == null || xbm.length < rowBytes || xbm.length % rowBytes != 0) {
      if (!mounted) return;
      context.showNotification('Invalid .bm file', type: QNotificationType.error);
      return;
    }
    final height = xbm.length ~/ rowBytes;
    _ctrl.importSinglePixelFrame(
      PaintCodec.xbmToPixels(xbm, srcWidth: kCanvasWidth, srcHeight: height),
    );
    if (!mounted) return;
    context.showNotification(
      '.bm imported as frame ${_ctrl.currentFrame + 1}',
      type: QNotificationType.good,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _close(),
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: EditorAppBar(
          ctrl: _ctrl,
          onClose: _close,
          onExport: _onExport,
        ),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final isWide = constraints.maxWidth > constraints.maxHeight;
                  return isWide
                      ? _buildWideLayout(colors)
                      : _buildNarrowLayout(colors);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(QAppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          const SizedBox(height: 10),
          CanvasView(ctrl: _ctrl),
          const SizedBox(height: 8),
          ColorAndZoomRow(ctrl: _ctrl, colors: colors),
          const SizedBox(height: 6),
          ToolRow(ctrl: _ctrl, colors: colors),
          const SizedBox(height: 6),
          OpsRow(ctrl: _ctrl, colors: colors),
          const SizedBox(height: 8),
          FramesSection(ctrl: _ctrl, colors: colors),
          const SizedBox(height: 8),
          AnimationPanel(ctrl: _ctrl, colors: colors),
          const SizedBox(height: 8),
          ExportRow(colors: colors, onExport: _showExportDialog, onImport: _onImport),
        ],
      ),
    );
  }

  Widget _buildWideLayout(QAppColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                const SizedBox(height: 10),
                CanvasView(ctrl: _ctrl),
                const SizedBox(height: 8),
                ColorAndZoomRow(ctrl: _ctrl, colors: colors),
                const SizedBox(height: 6),
                ToolRow(ctrl: _ctrl, colors: colors),
                const SizedBox(height: 6),
                OpsRow(ctrl: _ctrl, colors: colors),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.divider),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                const SizedBox(height: 10),
                FramesSection(ctrl: _ctrl, colors: colors),
                const SizedBox(height: 8),
                AnimationPanel(ctrl: _ctrl, colors: colors),
                const SizedBox(height: 8),
                ExportRow(colors: colors, onExport: _showExportDialog, onImport: _onImport),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
