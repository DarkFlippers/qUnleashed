import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
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
import 'painters.dart';

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
  Size? _canvasContainerSize;

  Offset _panOffset = Offset.zero;
  bool _isPanning = false;
  int? _panPointer;
  Offset _panStartLocal = Offset.zero;
  Offset _panStartOffset = Offset.zero;

  double _cLeft = 0.0;
  double _cTop = 0.0;
  double _pixelSize = 1.0;
  bool _isTwoFingerPanning = false;
  final Map<int, Offset> _touchPointers = {};
  Offset _twoFingerStartCentroid = Offset.zero;
  Offset _twoFingerStartPanOffset = Offset.zero;

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
      _ctrl.startVirtualDisplay();
      if (project != null) {
        await _loadProject(project);
      }
      // Whatever we loaded (or the empty start) is the clean baseline.
      _baselineVersion = _ctrl.pixelVersion;
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

  // Pan: right mouse button drag, scroll wheel, or two-finger touch.

  int _toCanvasX(double cx) =>
      ((cx - _cLeft) / _pixelSize).floor().clamp(0, kCanvasWidth - 1);
  int _toCanvasY(double cy) =>
      ((cy - _cTop) / _pixelSize).floor().clamp(0, kCanvasHeight - 1);

  bool _isInsideCanvas(Offset pos) =>
      pos.dx >= _cLeft &&
      pos.dx < _cLeft + kCanvasWidth * _pixelSize &&
      pos.dy >= _cTop &&
      pos.dy < _cTop + kCanvasHeight * _pixelSize;

  Offset _touchCentroid() {
    final vals = _touchPointers.values;
    return vals.fold(Offset.zero, (a, b) => a + b) / vals.length.toDouble();
  }

  void _onScrollPan(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final cs = _canvasContainerSize;
    if (cs == null) return;
    // Always consume so the parent ScrollView never scrolls over the canvas.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      if (event is! PointerScrollEvent) return;
      final ps = _ctrl.effectivePixelSize(cs.width);
      final maxX = ((kCanvasWidth * ps - cs.width) / 2).clamp(0.0, double.infinity);
      final maxY = ((kCanvasHeight * ps - cs.height) / 2).clamp(0.0, double.infinity);
      if (maxX == 0 && maxY == 0) return;
      setState(() {
        _panOffset = Offset(
          (_panOffset.dx - event.scrollDelta.dx).clamp(-maxX, maxX),
          (_panOffset.dy - event.scrollDelta.dy).clamp(-maxY, maxY),
        );
      });
    });
  }

  void _onPanDown(PointerDownEvent e) {
    if (e.buttons & 0x2 != 0) {
      _isPanning = true;
      _panPointer = e.pointer;
      _panStartLocal = e.localPosition;
      _panStartOffset = _panOffset;
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      _touchPointers[e.pointer] = e.localPosition;
      if (_touchPointers.length >= 2) {
        if (!_isTwoFingerPanning) {
          for (final en in _touchPointers.entries) {
            if (en.key != e.pointer) {
              _ctrl.onPointerUp(_toCanvasX(en.value.dx), _toCanvasY(en.value.dy), en.key);
            }
          }
          _isTwoFingerPanning = true;
          _twoFingerStartCentroid = _touchCentroid();
          _twoFingerStartPanOffset = _panOffset;
        }
        return;
      }
    }
    if (_isInsideCanvas(e.localPosition)) {
      _ctrl.onPointerDown(_toCanvasX(e.localPosition.dx), _toCanvasY(e.localPosition.dy), e.pointer);
    }
  }

  void _onPanMove(PointerMoveEvent e) {
    if (e.buttons & 0x2 != 0) {
      if (!_isPanning || e.pointer != _panPointer) return;
      final cs = _canvasContainerSize;
      if (cs == null) return;
      final ps = _ctrl.effectivePixelSize(cs.width);
      final maxX = ((kCanvasWidth * ps - cs.width) / 2).clamp(0.0, double.infinity);
      final maxY = ((kCanvasHeight * ps - cs.height) / 2).clamp(0.0, double.infinity);
      setState(() {
        _panOffset = Offset(
          (_panStartOffset.dx + e.localPosition.dx - _panStartLocal.dx).clamp(-maxX, maxX),
          (_panStartOffset.dy + e.localPosition.dy - _panStartLocal.dy).clamp(-maxY, maxY),
        );
      });
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      if (!_touchPointers.containsKey(e.pointer)) return;
      _touchPointers[e.pointer] = e.localPosition;
      if (_isTwoFingerPanning) {
        final cs = _canvasContainerSize;
        if (cs == null) return;
        final ps = _ctrl.effectivePixelSize(cs.width);
        final maxX = ((kCanvasWidth * ps - cs.width) / 2).clamp(0.0, double.infinity);
        final maxY = ((kCanvasHeight * ps - cs.height) / 2).clamp(0.0, double.infinity);
        final centroid = _touchCentroid();
        setState(() {
          _panOffset = Offset(
            (_twoFingerStartPanOffset.dx + centroid.dx - _twoFingerStartCentroid.dx).clamp(-maxX, maxX),
            (_twoFingerStartPanOffset.dy + centroid.dy - _twoFingerStartCentroid.dy).clamp(-maxY, maxY),
          );
        });
        return;
      }
      _ctrl.onPointerMove(_toCanvasX(e.localPosition.dx), _toCanvasY(e.localPosition.dy), e.pointer);
      return;
    }
    _ctrl.onPointerMove(_toCanvasX(e.localPosition.dx), _toCanvasY(e.localPosition.dy), e.pointer);
  }

  void _onPanUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touchPointers.remove(e.pointer);
      if (_isTwoFingerPanning) {
        if (_touchPointers.isEmpty) {
          _isTwoFingerPanning = false;
        } else {
          _twoFingerStartCentroid = _touchCentroid();
          _twoFingerStartPanOffset = _panOffset;
        }
        return;
      }
      _ctrl.onPointerUp(_toCanvasX(e.localPosition.dx), _toCanvasY(e.localPosition.dy), e.pointer);
      return;
    }
    if (e.pointer == _panPointer) {
      _isPanning = false;
      _panPointer = null;
      return;
    }
    _ctrl.onPointerUp(_toCanvasX(e.localPosition.dx), _toCanvasY(e.localPosition.dy), e.pointer);
  }

  void _onPanCancel(PointerCancelEvent e) {
    _touchPointers.remove(e.pointer);
    if (_isTwoFingerPanning && _touchPointers.isEmpty) _isTwoFingerPanning = false;
    if (e.pointer == _panPointer) {
      _isPanning = false;
      _panPointer = null;
    }
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final cs = _canvasContainerSize;
    if (cs == null) return;
    final ps = _ctrl.effectivePixelSize(cs.width);
    final maxX = ((kCanvasWidth * ps - cs.width) / 2).clamp(0.0, double.infinity);
    final maxY = ((kCanvasHeight * ps - cs.height) / 2).clamp(0.0, double.infinity);
    if (maxX == 0 && maxY == 0) return;
    setState(() {
      _panOffset = Offset(
        (_panOffset.dx + e.panDelta.dx).clamp(-maxX, maxX),
        (_panOffset.dy + e.panDelta.dy).clamp(-maxY, maxY),
      );
    });
  }

  void _zoomReset() {
    _ctrl.zoomReset();
    setState(() => _panOffset = Offset.zero);
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
            _AlertTile(
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
              _AlertTile(
                icon: Icons.gif_box_outlined,
                title: 'GIF Animation',
                subtitle: '$n frames',
                colors: colors,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportGif();
                },
              ),
            _AlertTile(
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
        if (xbm == null || xbm.length < 1024) continue;
        newFrames.add(PaintCodec.xbmToPixels(xbm));
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
    if (xbm == null || xbm.length < 1024) {
      if (!mounted) return;
      context.showNotification('Invalid .bm file', type: QNotificationType.error);
      return;
    }
    _ctrl.importSinglePixelFrame(PaintCodec.xbmToPixels(xbm));
    if (!mounted) return;
    context.showNotification(
      '.bm imported as frame ${_ctrl.currentFrame + 1}',
      type: QNotificationType.good,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _close(),
      child: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: [
            _buildAppBar(colors, topInset),
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
          _buildCanvas(colors),
          const SizedBox(height: 8),
          _buildColorAndZoomRow(colors),
          const SizedBox(height: 6),
          _buildToolRow(colors),
          const SizedBox(height: 6),
          _buildOpsRow(colors),
          const SizedBox(height: 8),
          _buildFramesSection(colors),
          const SizedBox(height: 8),
          _buildAnimationSection(colors),
          const SizedBox(height: 8),
          _buildExportRow(colors),
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
                _buildCanvas(colors),
                const SizedBox(height: 8),
                _buildColorAndZoomRow(colors),
                const SizedBox(height: 6),
                _buildToolRow(colors),
                const SizedBox(height: 6),
                _buildOpsRow(colors),
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
                _buildFramesSection(colors),
                const SizedBox(height: 8),
                _buildAnimationSection(colors),
                const SizedBox(height: 8),
                _buildExportRow(colors),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(QAppColors colors, double topInset) {
    return Container(
      color: colors.accent,
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              onPressed: _close,
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
              onPressed: _ctrl.canUndo ? _ctrl.undo : null,
              icon: Icon(Icons.undo, color: colors.onAccent),
              tooltip: 'Undo',
            ),
            IconButton(
              onPressed: _ctrl.canRedo ? _ctrl.redo : null,
              icon: Icon(Icons.redo, color: colors.onAccent),
              tooltip: 'Redo',
            ),
            IconButton(
              onPressed: _onExport,
              icon: Icon(Icons.save_outlined, color: colors.onAccent),
              tooltip: 'Save',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(QAppColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const hPad = 14.0;
        final containerW = constraints.maxWidth - hPad * 2;
        final basePs = (containerW - kPassivePad * 2) / kCanvasWidth;
        final containerH = kCanvasHeight * basePs + kPassivePad * 2;
        _canvasContainerSize = Size(containerW, containerH);
        final ps = _ctrl.effectivePixelSize(containerW);
        final canvasW = kCanvasWidth * ps;
        final canvasH = kCanvasHeight * ps;
        final maxPanX = ((canvasW - containerW) / 2).clamp(0.0, double.infinity);
        final maxPanY = ((canvasH - containerH) / 2).clamp(0.0, double.infinity);
        final panX = _panOffset.dx.clamp(-maxPanX, maxPanX);
        final panY = _panOffset.dy.clamp(-maxPanY, maxPanY);
        final cLeft = (containerW - canvasW) / 2 + panX;
        final cTop = (containerH - canvasH) / 2 + panY;
        _cLeft = cLeft;
        _cTop = cTop;
        _pixelSize = ps;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: hPad),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Claim scale/pan gestures so parent ScrollView never wins the arena.
            onScaleStart: (_) {},
            onScaleUpdate: (_) {},
            onScaleEnd: (_) {},
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPanDown,
              onPointerMove: _onPanMove,
              onPointerUp: _onPanUp,
              onPointerCancel: _onPanCancel,
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              onPointerSignal: _onScrollPan,
              child: Container(
                width: containerW,
                height: containerH,
                decoration: BoxDecoration(
                  color: colors.screenBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.screenBorder.withAlpha(30),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: cLeft,
                      top: cTop,
                      width: canvasW,
                      height: canvasH,
                      child: CustomPaint(
                        painter: CanvasPainter(
                          pixels: _ctrl.currentPixels,
                          previewPixels: _ctrl.previewPixels,
                          previewFg: _ctrl.drawFg,
                          pixelSize: ps,
                          showGrid: _ctrl.showGrid && ps >= 3.0,
                          fgColor: colors.screenBorder,
                          bgColor: colors.screenBackground,
                          previewColor: colors.accent,
                          version: _ctrl.pixelVersion,
                          onionPixels: _ctrl.showOnionSkin && _ctrl.currentFrame > 0
                              ? _ctrl.frames[_ctrl.currentFrame - 1]
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorAndZoomRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _ColorSwatch(
            color: colors.screenBorder,
            selected: _ctrl.drawFg,
            onTap: () => _ctrl.setDrawFg(true),
          ),
          const SizedBox(width: 6),
          _ColorSwatch(
            color: colors.screenBackground,
            selected: !_ctrl.drawFg,
            onTap: () => _ctrl.setDrawFg(false),
          ),
          const Spacer(),
          _IconToolButton(
            icon: Icons.grid_on,
            active: _ctrl.showGrid,
            colors: colors,
            onTap: () => _ctrl.setShowGrid(!_ctrl.showGrid),
            tooltip: 'Toggle grid',
          ),
          const SizedBox(width: 4),
          _IconToolButton(
            icon: Icons.zoom_out,
            active: false,
            colors: colors,
            onTap: _ctrl.zoomOut,
            tooltip: 'Zoom out',
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _zoomReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _ctrl.zoomLabel,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _IconToolButton(
            icon: Icons.zoom_in,
            active: false,
            colors: colors,
            onTap: _ctrl.zoomIn,
            tooltip: 'Zoom in',
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow(QAppColors colors) {
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
              child: _ToolButton(
                icon: drawTools[i].$2,
                active: _ctrl.tool == drawTools[i].$1,
                colors: colors,
                onTap: () => _ctrl.setTool(drawTools[i].$1),
                iconTransform: drawTools[i].$4,
                tooltip: drawTools[i].$3,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Expanded(
            child: _ToolButton(
              icon: Icons.layers_outlined,
              active: _ctrl.showOnionSkin,
              colors: colors,
              onTap: () => _ctrl.setShowOnionSkin(!_ctrl.showOnionSkin),
              tooltip: 'Onion skin',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpsRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _OpsButton(
              icon: Icons.flip,
              colors: colors,
              onTap: _ctrl.flipH,
              tooltip: 'Flip horizontal',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _OpsButton(
              icon: Icons.flip,
              iconTransform: Matrix4.rotationZ(math.pi / 2),
              colors: colors,
              onTap: _ctrl.flipV,
              tooltip: 'Flip vertical',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _OpsButton(
              icon: Icons.contrast,
              colors: colors,
              onTap: _ctrl.invert,
              tooltip: 'Invert',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _OpsButton(
              icon: Icons.delete_outline,
              colors: colors,
              onTap: _ctrl.clearFrame,
              tooltip: 'Clear',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFramesSection(QAppColors colors) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
              child: Row(
                children: [
                  Text(
                    'FRAMES · ${_ctrl.frames.length}',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _ctrl.frames.length > 1 ? _ctrl.togglePlay : null,
                    icon: Icon(
                      _ctrl.isPlaying ? Icons.stop : Icons.play_arrow,
                      size: 16,
                      color: _ctrl.frames.length > 1 ? colors.accent : colors.textMuted,
                    ),
                    label: Text(
                      _ctrl.isPlaying ? 'Stop' : 'Play',
                      style: TextStyle(
                        color: _ctrl.frames.length > 1 ? colors.accent : colors.textMuted,
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
            ),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Expanded(
                    child: ReorderableListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
                      buildDefaultDragHandles: false,
                      onReorderItem: _ctrl.reorderFrame,
                      children: [
                        for (int i = 0; i < _ctrl.frames.length; i++)
                          ReorderableDragStartListener(
                            key: ValueKey(i),
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildFrameThumbnail(i, colors),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 14, 6),
                    child: GestureDetector(
                      onTap: _ctrl.addFrame,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _FrameActionButton(
                      icon: Icons.copy_outlined,
                      label: 'Duplicate',
                      colors: colors,
                      onTap: _ctrl.duplicateFrame,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FrameActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      colors: colors,
                      onTap: _ctrl.deleteFrame,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: (_ctrl.effectivePassiveCount < _ctrl.frames.length) ? 1.0 : 0.38,
                    child: IgnorePointer(
                      ignoring: _ctrl.effectivePassiveCount >= _ctrl.frames.length,
                      child: _FrameActionButton(
                        icon: Icons.touch_app_outlined,
                        label: '',
                        colors: colors,
                        onTap: _ctrl.triggerActive,
                        accent: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameThumbnail(int i, QAppColors colors) {
    final selected = i == _ctrl.currentFrame;
    final isActive = i >= _ctrl.effectivePassiveCount;
    final borderColor = selected
        ? colors.accent
        : isActive
            ? colors.accent.withAlpha(80)
            : colors.divider;
    return GestureDetector(
      onTap: () => _ctrl.selectFrame(i),
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor, width: selected ? 2.0 : 1.0),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                painter: ThumbnailPainter(
                  pixels: _ctrl.frames[i],
                  fgColor: colors.screenBorder,
                  bgColor: colors.screenBackground,
                  version: _ctrl.pixelVersion,
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

  Widget _buildAnimationSection(QAppColors colors) {
    final n = _ctrl.frames.length;
    final passiveN = _ctrl.effectivePassiveCount;
    final activeN = n - passiveN;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'ANIMATION',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _ctrl.setCompressBm(!_ctrl.compressBm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _ctrl.compressBm
                          ? colors.accent.withAlpha(30)
                          : colors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _ctrl.compressBm ? colors.accent : colors.divider,
                      ),
                    ),
                    child: Text(
                      _ctrl.compressBm ? 'Compress ✓' : 'Compress',
                      style: TextStyle(
                        color: _ctrl.compressBm ? colors.accent : colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Frame rate',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colors.accent,
                      thumbColor: colors.accent,
                      inactiveTrackColor: colors.divider,
                      overlayColor: colors.accent.withAlpha(30),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _ctrl.frameRate.toDouble().clamp(1, 30),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      onChanged: (v) => _ctrl.setFrameRate(v.round()),
                    ),
                  ),
                ),
                Text(
                  '${_ctrl.frameRate} fps',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            Row(
              children: [
                Text(
                  'Passive  $passiveN',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  'Active  $activeN',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.accent,
                thumbColor: colors.accent,
                inactiveTrackColor: colors.divider.withAlpha(180),
                overlayColor: colors.accent.withAlpha(30),
                trackHeight: 3,
              ),
              child: Slider(
                value: passiveN.toDouble().clamp(0, math.max(n, 1).toDouble()),
                min: 0,
                max: math.max(n, 1).toDouble(),
                divisions: math.max(n, 1),
                onChanged: n > 1 ? (v) => _ctrl.setPassiveFrameCount(v.round()) : null,
              ),
            ),
            const SizedBox(height: 4),
            _AnimRow(
              label: 'Duration',
              unit: 's',
              colors: colors,
              trailing: _Stepper(
                value: _ctrl.duration,
                min: 1,
                max: 99999,
                colors: colors,
                onChange: _ctrl.setDuration,
              ),
            ),
            Opacity(
              opacity: activeN > 0 ? 1.0 : 0.38,
              child: IgnorePointer(
                ignoring: activeN == 0,
                child: Column(
                  children: [
                    _AnimRow(
                      label: 'Active cycles',
                      colors: colors,
                      trailing: _Stepper(
                        value: _ctrl.activeCycles,
                        min: 1,
                        max: 99,
                        colors: colors,
                        onChange: _ctrl.setActiveCycles,
                      ),
                    ),
                    _AnimRow(
                      label: 'Active cooldown',
                      unit: 's',
                      colors: colors,
                      trailing: _Stepper(
                        value: _ctrl.activeCooldown,
                        min: 0,
                        max: 3600,
                        colors: colors,
                        onChange: _ctrl.setActiveCooldown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _ctrl.triggerActive,
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors.accent.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.accent.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app_outlined, size: 15, color: colors.accent),
                            const SizedBox(width: 6),
                            Text(
                              'Trigger Active',
                              style: TextStyle(
                                color: colors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _ExportButton(
              icon: Icons.upload_outlined,
              label: 'Export',
              colors: colors,
              onTap: _showExportDialog,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExportButton(
              icon: Icons.download_outlined,
              label: 'Import',
              colors: colors,
              onTap: _onImport,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? accent : Colors.grey.withAlpha(80),
            width: selected ? 2.5 : 1.0,
          ),
        ),
      ),
    );
  }
}

class _IconToolButton extends StatelessWidget {
  const _IconToolButton({
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final QAppColors colors;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? colors.accent : colors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? colors.onAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
    this.iconTransform,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final QAppColors colors;
  final VoidCallback onTap;
  final Matrix4? iconTransform;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: active ? colors.accent : colors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: iconTransform != null
                ? Transform(
                    transform: iconTransform!,
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 20,
                      color: active ? colors.onAccent : colors.textSecondary,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: active ? colors.onAccent : colors.textSecondary,
                  ),
          ),
        ),
      ),
    );
  }
}

class _OpsButton extends StatelessWidget {
  const _OpsButton({
    required this.icon,
    required this.colors,
    required this.onTap,
    this.iconTransform,
    this.tooltip,
  });

  final IconData icon;
  final QAppColors colors;
  final VoidCallback onTap;
  final Matrix4? iconTransform;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: iconTransform != null
                ? Transform(
                    transform: iconTransform!,
                    alignment: Alignment.center,
                    child: Icon(icon, size: 20, color: colors.textSecondary),
                  )
                : Icon(icon, size: 20, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _FrameActionButton extends StatelessWidget {
  const _FrameActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final QAppColors colors;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? colors.accent : colors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        width: label.isEmpty ? 40 : null,
        decoration: BoxDecoration(
          color: accent ? colors.accent.withAlpha(20) : colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent ? colors.accent.withAlpha(80) : colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: colors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? colors.background : colors.background.withAlpha(80),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.divider),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? colors.textPrimary : colors.textMuted,
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.colors,
    required this.onChange,
  });

  final int value;
  final int min;
  final int max;
  final QAppColors colors;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          enabled: value > min,
          colors: colors,
          onTap: () => onChange((value - 1).clamp(min, max)),
        ),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          enabled: value < max,
          colors: colors,
          onTap: () => onChange((value + 1).clamp(min, max)),
        ),
      ],
    );
  }
}

class _AnimRow extends StatelessWidget {
  const _AnimRow({
    required this.label,
    required this.colors,
    required this.trailing,
    this.unit,
  });

  final String label;
  final String? unit;
  final QAppColors colors;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          if (unit != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                unit!,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ),
          trailing,
        ],
      ),
    );
  }
}
