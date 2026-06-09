import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';

import '../../services/repository/app.dart';
import '../../theme.dart';
import '../../widgets/notification.dart';
import '../remote/gif_encoder.dart';

// ── Canvas constants ──────────────────────────────────────────────────────────
const int _kW = 128;
const int _kH = 64;
const int _kMaxUndo = 20;
const int _kAnimFrameDelay = 200; // ms per animation frame

// ── Drawing tools ─────────────────────────────────────────────────────────────
enum _Tool { pencil, eraser, fill, line, rect, ellipse }

// ── Zoom levels ───────────────────────────────────────────────────────────────
const List<double> _kZooms = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0];

// ─────────────────────────────────────────────────────────────────────────────
class PaintPage extends StatefulWidget {
  const PaintPage({super.key});

  @override
  State<PaintPage> createState() => _PaintPageState();
}

class _PaintPageState extends State<PaintPage> {
  // ── Pixel data ──────────────────────────────────────────────────────────────
  // Each frame: Uint8List of length _kW * _kH, 0 = bg, 1 = fg
  final List<Uint8List> _frames = [Uint8List(_kW * _kH)];
  int _currentFrame = 0;

  // ── Undo / redo ─────────────────────────────────────────────────────────────
  final List<List<Uint8List>> _undoStack = [];
  final List<List<Uint8List>> _redoStack = [];

  // ── Drawing state ───────────────────────────────────────────────────────────
  _Tool _tool = _Tool.pencil;
  bool _drawFg = true; // true = draw foreground (dark)
  bool _showGrid = false;
  int _zoomIdx = 1; // index into _kZooms, default 1x

  // Preview pixels during line / rect / ellipse drag
  int? _strokeStartX, _strokeStartY;
  List<int>? _previewPixels; // flat set of pixel indices to preview
  int? _lastPencilX, _lastPencilY; // for pencil interpolation

  // ── Animation ───────────────────────────────────────────────────────────────
  Timer? _playTimer;
  bool _isPlaying = false;

  // ── Virtual display ─────────────────────────────────────────────────────────
  final FlipperClient _client = FlipperOneClient().get();
  bool _virtualDisplayActive = false;
  bool _closing = false;
  Timer? _pushTimer;

  // ── Canvas size cache ───────────────────────────────────────────────────────
  Size? _canvasContainerSize;
  int? _activePointer;

  // ── Getters ─────────────────────────────────────────────────────────────────
  Uint8List get _pixels => _frames[_currentFrame];

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startVirtualDisplay());
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _pushTimer?.cancel();
    if (!_closing) _stopVirtualDisplay();
    super.dispose();
  }

  // ── Virtual display ──────────────────────────────────────────────────────────

  Future<void> _startVirtualDisplay() async {
    try {
      await _client.guiStartVirtualDisplay(
        StartVirtualDisplayRequest(),
        priority: FlipperRequestPriority.rightNow,
      );
      _virtualDisplayActive = true;
    } on FlipperRpcVirtualDisplayAlreadyStartedException {
      // Left open from a previous session — stop and restart clean
      try {
        await _client.guiStopVirtualDisplay();
        await _client.guiStartVirtualDisplay(StartVirtualDisplayRequest());
        _virtualDisplayActive = true;
      } catch (e) {
        LogService.log('[PaintPage] restart virtual display failed: $e');
      }
    } catch (e) {
      LogService.log('[PaintPage] start virtual display failed: $e');
    }
  }

  Future<void> _stopVirtualDisplay() async {
    try {
      await _client
          .guiStopVirtualDisplay()
          .timeout(const Duration(seconds: 2));
      _virtualDisplayActive = false;
    } catch (_) {}
  }

  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 100), _pushToDevice);
  }

  Future<void> _pushToDevice() async {
    if (!_virtualDisplayActive) return;
    try {
      final data = _encodeXBM(_frames[_currentFrame]);
      // Send frame update without stop/start — fire-and-forget via guiScreenFrame
      await _client.sendRpc(
        Main(guiScreenFrame: ScreenFrame(data: data)),
        priority: FlipperRequestPriority.rightNow,
      );
    } catch (e) {
      LogService.log('[PaintPage] push frame failed: $e');
    }
  }

  /// XBM format: row-major, LSB = leftmost pixel in each byte group.
  /// 64 rows × 16 bytes = 1024 bytes total.
  static Uint8List _encodeXBM(Uint8List pixels) {
    final data = Uint8List(1024);
    for (int y = 0; y < _kH; y++) {
      for (int x = 0; x < _kW; x++) {
        if (pixels[y * _kW + x] != 0) {
          data[y * 16 + (x ~/ 8)] |= (1 << (x & 7));
        }
      }
    }
    return data;
  }

  // ── Undo / redo ──────────────────────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(_frames.map((f) => Uint8List.fromList(f)).toList());
    if (_undoStack.length > _kMaxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_frames.map((f) => Uint8List.fromList(f)).toList());
    final prev = _undoStack.removeLast();
    _frames
      ..clear()
      ..addAll(prev);
    _currentFrame = _currentFrame.clamp(0, _frames.length - 1);
    _schedulePush();
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_frames.map((f) => Uint8List.fromList(f)).toList());
    final next = _redoStack.removeLast();
    _frames
      ..clear()
      ..addAll(next);
    _currentFrame = _currentFrame.clamp(0, _frames.length - 1);
    _schedulePush();
    setState(() {});
  }

  // ── Drawing algorithms ───────────────────────────────────────────────────────

  void _setPixel(int x, int y, bool fg, [Uint8List? target]) {
    if (x < 0 || x >= _kW || y < 0 || y >= _kH) return;
    final t = target ?? _pixels;
    t[y * _kW + x] = fg ? 1 : 0;
  }

  void _drawLine(int x0, int y0, int x1, int y1, bool fg,
      [Uint8List? target]) {
    for (final p in _bresenham(x0, y0, x1, y1)) {
      _setPixel(p.$1, p.$2, fg, target);
    }
  }

  void _drawRect(int x0, int y0, int x1, int y1, bool fg,
      [Uint8List? target]) {
    final minX = math.min(x0, x1);
    final maxX = math.max(x0, x1);
    final minY = math.min(y0, y1);
    final maxY = math.max(y0, y1);
    for (int x = minX; x <= maxX; x++) {
      _setPixel(x, minY, fg, target);
      _setPixel(x, maxY, fg, target);
    }
    for (int y = minY + 1; y < maxY; y++) {
      _setPixel(minX, y, fg, target);
      _setPixel(maxX, y, fg, target);
    }
  }

  void _drawEllipse(int cx, int cy, int rx, int ry, bool fg,
      [Uint8List? target]) {
    if (rx <= 0 || ry <= 0) {
      _setPixel(cx, cy, fg, target);
      return;
    }
    for (final p in _ellipsePoints(cx, cy, rx, ry)) {
      _setPixel(p.$1, p.$2, fg, target);
    }
  }

  void _floodFill(int x, int y, bool fg) {
    final target = _pixels[y * _kW + x];
    final fill = fg ? 1 : 0;
    if (target == fill) return;
    final queue = <int>[y * _kW + x];
    final visited = Uint8List(_kW * _kH);
    visited[y * _kW + x] = 1;
    while (queue.isNotEmpty) {
      final idx = queue.removeLast();
      _pixels[idx] = fill;
      final px = idx % _kW;
      final py = idx ~/ _kW;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = px + d.$1;
        final ny = py + d.$2;
        if (nx < 0 || nx >= _kW || ny < 0 || ny >= _kH) continue;
        final ni = ny * _kW + nx;
        if (visited[ni] != 0 || _pixels[ni] != target) continue;
        visited[ni] = 1;
        queue.add(ni);
      }
    }
  }

  // ── Stroke operations ────────────────────────────────────────────────────────

  /// Builds a preview pixel list for shape tools (line, rect, ellipse).
  List<int> _buildPreview(int x0, int y0, int x1, int y1) {
    final preview = <int>[];
    List<(int, int)> pts;
    switch (_tool) {
      case _Tool.line:
        pts = _bresenham(x0, y0, x1, y1);
      case _Tool.rect:
        pts = _rectOutline(x0, y0, x1, y1);
      case _Tool.ellipse:
        final rx = (x1 - x0).abs() ~/ 2;
        final ry = (y1 - y0).abs() ~/ 2;
        final cx = math.min(x0, x1) + rx;
        final cy = math.min(y0, y1) + ry;
        pts = _ellipsePoints(cx, cy, rx, ry);
      default:
        return [];
    }
    for (final p in pts) {
      if (p.$1 >= 0 && p.$1 < _kW && p.$2 >= 0 && p.$2 < _kH) {
        preview.add(p.$2 * _kW + p.$1);
      }
    }
    return preview;
  }

  void _commitPreview(int x1, int y1) {
    final x0 = _strokeStartX;
    final y0 = _strokeStartY;
    if (x0 == null || y0 == null) return;
    switch (_tool) {
      case _Tool.line:
        _drawLine(x0, y0, x1, y1, _drawFg);
      case _Tool.rect:
        _drawRect(x0, y0, x1, y1, _drawFg);
      case _Tool.ellipse:
        final rx = (x1 - x0).abs() ~/ 2;
        final ry = (y1 - y0).abs() ~/ 2;
        final cx = math.min(x0, x1) + rx;
        final cy = math.min(y0, y1) + ry;
        _drawEllipse(cx, cy, rx, ry, _drawFg);
      default:
        break;
    }
  }

  // ── Pointer handling ─────────────────────────────────────────────────────────

  (int, int) _toPixelCoord(Offset local) {
    final cs = _canvasContainerSize;
    if (cs == null) return (0, 0);
    final ps = _effectivePixelSize(cs.width);
    final canvasW = _kW * ps;
    final canvasH = _kH * ps;
    final ox = (cs.width - canvasW) / 2.0;
    final oy = (cs.height - canvasH) / 2.0;
    final px = ((local.dx - ox) / ps).floor().clamp(0, _kW - 1);
    final py = ((local.dy - oy) / ps).floor().clamp(0, _kH - 1);
    return (px, py);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_activePointer != null) return;
    _activePointer = e.pointer;
    final (x, y) = _toPixelCoord(e.localPosition);

    switch (_tool) {
      case _Tool.pencil:
      case _Tool.eraser:
        _pushUndo();
        _setPixel(x, y, _tool == _Tool.pencil ? _drawFg : !_drawFg);
        _lastPencilX = x;
        _lastPencilY = y;
        _schedulePush();
        setState(() {});
      case _Tool.fill:
        _pushUndo();
        _floodFill(x, y, _drawFg);
        _schedulePush();
        setState(() {});
      case _Tool.line:
      case _Tool.rect:
      case _Tool.ellipse:
        _strokeStartX = x;
        _strokeStartY = y;
        _previewPixels = [];
        setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    final (x, y) = _toPixelCoord(e.localPosition);

    switch (_tool) {
      case _Tool.pencil:
      case _Tool.eraser:
        final lx = _lastPencilX;
        final ly = _lastPencilY;
        if (lx != null && ly != null && (lx != x || ly != y)) {
          for (final p in _bresenham(lx, ly, x, y)) {
            _setPixel(p.$1, p.$2, _tool == _Tool.pencil ? _drawFg : !_drawFg);
          }
        }
        _lastPencilX = x;
        _lastPencilY = y;
        _schedulePush();
        setState(() {});
      case _Tool.fill:
        break;
      case _Tool.line:
      case _Tool.rect:
      case _Tool.ellipse:
        final x0 = _strokeStartX;
        final y0 = _strokeStartY;
        if (x0 == null || y0 == null) return;
        _previewPixels = _buildPreview(x0, y0, x, y);
        setState(() {});
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    final (x, y) = _toPixelCoord(e.localPosition);

    switch (_tool) {
      case _Tool.pencil:
      case _Tool.eraser:
      case _Tool.fill:
        _lastPencilX = null;
        _lastPencilY = null;
      case _Tool.line:
      case _Tool.rect:
      case _Tool.ellipse:
        _pushUndo();
        _commitPreview(x, y);
        _strokeStartX = null;
        _strokeStartY = null;
        _previewPixels = null;
        _schedulePush();
        setState(() {});
    }
  }

  // ── Operations ───────────────────────────────────────────────────────────────

  void _flipH() {
    _pushUndo();
    final p = _pixels;
    for (int y = 0; y < _kH; y++) {
      for (int x = 0; x < _kW ~/ 2; x++) {
        final a = y * _kW + x;
        final b = y * _kW + (_kW - 1 - x);
        final tmp = p[a];
        p[a] = p[b];
        p[b] = tmp;
      }
    }
    _schedulePush();
    setState(() {});
  }

  void _flipV() {
    _pushUndo();
    final p = _pixels;
    for (int y = 0; y < _kH ~/ 2; y++) {
      for (int x = 0; x < _kW; x++) {
        final a = y * _kW + x;
        final b = (_kH - 1 - y) * _kW + x;
        final tmp = p[a];
        p[a] = p[b];
        p[b] = tmp;
      }
    }
    _schedulePush();
    setState(() {});
  }

  void _invert() {
    _pushUndo();
    final p = _pixels;
    for (int i = 0; i < p.length; i++) {
      p[i] = p[i] == 0 ? 1 : 0;
    }
    _schedulePush();
    setState(() {});
  }

  void _clearFrame() {
    _pushUndo();
    _pixels.fillRange(0, _pixels.length, 0);
    _schedulePush();
    setState(() {});
  }

  // ── Frames ───────────────────────────────────────────────────────────────────

  void _addFrame() {
    _pushUndo();
    _frames.insert(_currentFrame + 1, Uint8List(_kW * _kH));
    _currentFrame++;
    _schedulePush();
    setState(() {});
  }

  void _duplicateFrame() {
    _pushUndo();
    _frames.insert(
      _currentFrame + 1,
      Uint8List.fromList(_frames[_currentFrame]),
    );
    _currentFrame++;
    _schedulePush();
    setState(() {});
  }

  void _deleteFrame() {
    if (_frames.length <= 1) {
      _clearFrame();
      return;
    }
    _pushUndo();
    _frames.removeAt(_currentFrame);
    _currentFrame = _currentFrame.clamp(0, _frames.length - 1);
    _schedulePush();
    setState(() {});
  }

  void _selectFrame(int idx) {
    if (idx == _currentFrame) return;
    _isPlaying = false;
    _playTimer?.cancel();
    _currentFrame = idx;
    _schedulePush();
    setState(() {});
  }

  void _togglePlay() {
    if (_isPlaying) {
      _isPlaying = false;
      _playTimer?.cancel();
      setState(() {});
    } else {
      _isPlaying = true;
      setState(() {});
      _playTimer = Timer.periodic(
        Duration(milliseconds: _kAnimFrameDelay),
        (_) {
          if (!mounted) return;
          _currentFrame = (_currentFrame + 1) % _frames.length;
          _schedulePush();
          setState(() {});
        },
      );
    }
  }

  // ── Zoom ─────────────────────────────────────────────────────────────────────

  double _effectivePixelSize(double containerWidth) {
    return (containerWidth / _kW) * _kZooms[_zoomIdx];
  }

  String _zoomLabel() {
    final z = _kZooms[_zoomIdx];
    return z == z.truncateToDouble() ? '${z.toInt()}x' : '${z}x';
  }

  void _zoomIn() {
    if (_zoomIdx < _kZooms.length - 1) setState(() => _zoomIdx++);
  }

  void _zoomOut() {
    if (_zoomIdx > 0) setState(() => _zoomIdx--);
  }

  void _zoomReset() => setState(() => _zoomIdx = 1);

  // ── PNG export/import ────────────────────────────────────────────────────────

  Future<void> _exportPng() async {
    try {
      final png = await _frameToPng(_frames[_currentFrame]);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dir = await appDrawingsDirectory();
      final file = io.File(pathJoin([dir.path, 'drawing_$ts.png']));
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      context.showNotification(
        'Saved: ${file.path}',
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Export failed: $e',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _exportGif() async {
    try {
      final gifFrames = _frames
          .map((f) => Uint8List.fromList(f))
          .toList();
      final delays = List.filled(_frames.length, _kAnimFrameDelay);
      final gif = FlipperGifEncoder.encode(
        width: _kW,
        height: _kH,
        frames: gifFrames,
        delaysMs: delays,
        color0: const Color(0xFFDFDFDF).toARGB32(),
        color1: const Color(0xFF000000).toARGB32(),
        scale: 2,
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dir = await appAnimationsDirectory();
      final file = io.File(pathJoin([dir.path, 'animation_$ts.gif']));
      await file.writeAsBytes(gif, flush: true);
      if (!mounted) return;
      context.showNotification(
        'Saved: ${file.path}',
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Export failed: $e',
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _onExport() async {
    if (_frames.length > 1) {
      await _exportGif();
    } else {
      await _exportPng();
    }
  }

  Future<void> _onImportPng() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _kW,
        targetHeight: _kH,
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return;
      final rgba = bd.buffer.asUint8List();

      _pushUndo();
      final dst = _pixels;
      for (int i = 0; i < _kW * _kH; i++) {
        final r = rgba[i * 4];
        final g = rgba[i * 4 + 1];
        final b = rgba[i * 4 + 2];
        // luminance threshold
        final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
        dst[i] = lum < 128 ? 1 : 0;
      }
      img.dispose();
      _schedulePush();
      setState(() {});
      if (!mounted) return;
      context.showNotification(
        'Image imported',
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        'Import failed: $e',
        type: QNotificationType.error,
      );
    }
  }

  // ── PNG encode helper ────────────────────────────────────────────────────────

  Future<Uint8List> _frameToPng(Uint8List pixels) async {
    final rgba = Uint8List(_kW * _kH * 4);
    const bg = 0xFFDFDFDF; // ARGB
    const fg = 0xFF000000;
    for (int i = 0; i < _kW * _kH; i++) {
      final c = pixels[i] != 0 ? fg : bg;
      rgba[i * 4] = (c >> 16) & 0xFF; // R
      rgba[i * 4 + 1] = (c >> 8) & 0xFF; // G
      rgba[i * 4 + 2] = c & 0xFF; // B
      rgba[i * 4 + 3] = (c >> 24) & 0xFF; // A
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      _kW,
      _kH,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final img = await completer.future;
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd!.buffer.asUint8List();
  }

  // ── Close ────────────────────────────────────────────────────────────────────

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _playTimer?.cancel();
    _pushTimer?.cancel();
    await _stopVirtualDisplay();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
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
                    _buildExportRow(colors),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────────────────

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
              onPressed: _undoStack.isEmpty ? null : _undo,
              icon: Icon(Icons.undo, color: colors.onAccent),
              tooltip: 'Undo',
            ),
            IconButton(
              onPressed: _redoStack.isEmpty ? null : _redo,
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

  // ── Canvas ───────────────────────────────────────────────────────────────────

  Widget _buildCanvas(QAppColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final containerH = math.max(160.0, w / 2.2);
        _canvasContainerSize = Size(w, containerH);
        final ps = _effectivePixelSize(w);

        return Container(
          width: w,
          height: containerH,
          decoration: BoxDecoration(
            color: colors.screenBackground,
            border: Border(
              top: BorderSide(color: colors.divider),
              bottom: BorderSide(color: colors.divider),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: Center(
              child: SizedBox(
                width: _kW * ps,
                height: _kH * ps,
                child: CustomPaint(
                  painter: _CanvasPainter(
                    pixels: _pixels,
                    previewPixels: _previewPixels,
                    previewFg: _drawFg,
                    pixelSize: ps,
                    showGrid: _showGrid && ps >= 3.0,
                    fgColor: colors.screenBorder,
                    bgColor: colors.screenBackground,
                    previewColor: colors.accent,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Color + zoom row ─────────────────────────────────────────────────────────

  Widget _buildColorAndZoomRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          // Foreground swatch
          _ColorSwatch(
            color: colors.screenBorder,
            selected: _drawFg,
            onTap: () => setState(() => _drawFg = true),
          ),
          const SizedBox(width: 6),
          // Background swatch
          _ColorSwatch(
            color: colors.screenBackground,
            selected: !_drawFg,
            onTap: () => setState(() => _drawFg = false),
          ),
          const Spacer(),
          // Grid toggle
          _IconToolButton(
            icon: Icons.grid_on,
            active: _showGrid,
            colors: colors,
            onTap: () => setState(() => _showGrid = !_showGrid),
            tooltip: 'Toggle grid',
          ),
          const SizedBox(width: 4),
          // Zoom out
          _IconToolButton(
            icon: Icons.zoom_out,
            active: false,
            colors: colors,
            onTap: _zoomOut,
            tooltip: 'Zoom out',
          ),
          const SizedBox(width: 4),
          // Zoom label / reset
          GestureDetector(
            onTap: _zoomReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _zoomLabel(),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Zoom in
          _IconToolButton(
            icon: Icons.zoom_in,
            active: false,
            colors: colors,
            onTap: _zoomIn,
            tooltip: 'Zoom in',
          ),
        ],
      ),
    );
  }

  // ── Tool row ─────────────────────────────────────────────────────────────────

  Widget _buildToolRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _ToolButton(
              icon: Icons.edit_outlined,
              active: _tool == _Tool.pencil,
              colors: colors,
              onTap: () => setState(() => _tool = _Tool.pencil),
              tooltip: 'Pencil',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ToolButton(
              icon: Icons.auto_fix_normal,
              active: _tool == _Tool.eraser,
              colors: colors,
              onTap: () => setState(() => _tool = _Tool.eraser),
              tooltip: 'Eraser',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ToolButton(
              icon: Icons.format_color_fill,
              active: _tool == _Tool.fill,
              colors: colors,
              onTap: () => setState(() => _tool = _Tool.fill),
              tooltip: 'Fill',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ToolButton(
              icon: Icons.remove,
              iconTransform: Matrix4.rotationZ(-math.pi / 4),
              active: _tool == _Tool.line,
              colors: colors,
              onTap: () => setState(() => _tool = _Tool.line),
              tooltip: 'Line',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ToolButton(
              icon: Icons.crop_square,
              active: _tool == _Tool.rect,
              colors: colors,
              onTap: () => setState(() => _tool = _Tool.rect),
              tooltip: 'Rectangle',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ToolButton(
              icon: Icons.radio_button_unchecked,
              active: _tool == _Tool.ellipse,
              colors: colors,
              onTap: () => setState(() => _tool = _Tool.ellipse),
              tooltip: 'Ellipse',
            ),
          ),
        ],
      ),
    );
  }

  // ── Operations row ───────────────────────────────────────────────────────────

  Widget _buildOpsRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _OpsButton(
              icon: Icons.flip,
              label: '',
              colors: colors,
              onTap: _flipH,
              tooltip: 'Flip horizontal',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _OpsButton(
              icon: Icons.flip,
              iconTransform: Matrix4.rotationZ(math.pi / 2),
              label: '',
              colors: colors,
              onTap: _flipV,
              tooltip: 'Flip vertical',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _OpsButton(
              icon: Icons.contrast,
              label: '',
              colors: colors,
              onTap: _invert,
              tooltip: 'Invert',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _OpsButton(
              icon: Icons.delete_outline,
              label: '',
              colors: colors,
              onTap: _clearFrame,
              tooltip: 'Clear',
            ),
          ),
        ],
      ),
    );
  }

  // ── Frames section ────────────────────────────────────────────────────────────

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
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
              child: Row(
                children: [
                  Text(
                    'FRAMES · ${_frames.length}',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  // Play button
                  TextButton.icon(
                    onPressed: _frames.length > 1 ? _togglePlay : null,
                    icon: Icon(
                      _isPlaying ? Icons.stop : Icons.play_arrow,
                      size: 16,
                      color: _frames.length > 1
                          ? colors.accent
                          : colors.textMuted,
                    ),
                    label: Text(
                      _isPlaying ? 'Stop' : 'Play',
                      style: TextStyle(
                        color: _frames.length > 1
                            ? colors.accent
                            : colors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            // Thumbnails
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                itemCount: _frames.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  if (i == _frames.length) {
                    // Add frame button
                    return GestureDetector(
                      onTap: _addFrame,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colors.divider,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.add,
                          color: colors.textMuted,
                          size: 20,
                        ),
                      ),
                    );
                  }
                  final selected = i == _currentFrame;
                  return GestureDetector(
                    onTap: () => _selectFrame(i),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selected ? colors.accent : colors.divider,
                          width: selected ? 2.0 : 1.0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: CustomPaint(
                          painter: _ThumbnailPainter(
                            pixels: _frames[i],
                            fgColor: colors.screenBorder,
                            bgColor: colors.screenBackground,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            // Duplicate / Delete
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _FrameActionButton(
                      icon: Icons.copy_outlined,
                      label: 'Duplicate',
                      colors: colors,
                      onTap: _duplicateFrame,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FrameActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      colors: colors,
                      onTap: _deleteFrame,
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

  // ── Export / Import row ──────────────────────────────────────────────────────

  Widget _buildExportRow(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _ExportButton(
              icon: Icons.upload_outlined,
              label: 'Export PNG',
              colors: colors,
              onTap: _frames.length > 1 ? _exportGif : _exportPng,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExportButton(
              icon: Icons.download_outlined,
              label: 'Import PNG',
              colors: colors,
              onTap: _onImportPng,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pixel geometry helpers ────────────────────────────────────────────────────

List<(int, int)> _bresenham(int x0, int y0, int x1, int y1) {
  final pts = <(int, int)>[];
  int dx = (x1 - x0).abs();
  int dy = -(y1 - y0).abs();
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx + dy;
  while (true) {
    pts.add((x0, y0));
    if (x0 == x1 && y0 == y1) break;
    final e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
  }
  return pts;
}

List<(int, int)> _rectOutline(int x0, int y0, int x1, int y1) {
  final minX = math.min(x0, x1);
  final maxX = math.max(x0, x1);
  final minY = math.min(y0, y1);
  final maxY = math.max(y0, y1);
  final pts = <(int, int)>[];
  for (int x = minX; x <= maxX; x++) {
    pts.add((x, minY));
    if (minY != maxY) pts.add((x, maxY));
  }
  for (int y = minY + 1; y < maxY; y++) {
    pts.add((minX, y));
    if (minX != maxX) pts.add((maxX, y));
  }
  return pts;
}

List<(int, int)> _ellipsePoints(int cx, int cy, int rx, int ry) {
  final pts = <(int, int)>{};
  if (rx == 0 && ry == 0) {
    pts.add((cx, cy));
    return pts.toList();
  }
  int x = 0;
  int y = ry;
  int rx2 = rx * rx;
  int ry2 = ry * ry;
  int p = ry2 - rx2 * ry + (rx2 ~/ 4);

  void add4(int x, int y) {
    pts.add((cx + x, cy + y));
    pts.add((cx - x, cy + y));
    pts.add((cx + x, cy - y));
    pts.add((cx - x, cy - y));
  }

  while (2 * ry2 * x <= 2 * rx2 * y) {
    add4(x, y);
    x++;
    if (p < 0) {
      p += 2 * ry2 * x + ry2;
    } else {
      y--;
      p += 2 * ry2 * x - 2 * rx2 * y + ry2;
    }
  }
  p = ry2 * (x + 1) * (x + 1) ~/ 1 +
      rx2 * (y - 1) * (y - 1) -
      rx2 * ry2 +
      ry2 * (2 * x + 3) ~/ 2 -
      rx2 * 2 * y;
  while (y >= 0) {
    add4(x, y);
    y--;
    if (p > 0) {
      p += rx2 - 2 * rx2 * y;
    } else {
      x++;
      p += 2 * ry2 * x - 2 * rx2 * y + rx2;
    }
  }
  return pts.toList();
}

// ── CustomPainters ────────────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.pixels,
    required this.pixelSize,
    required this.fgColor,
    required this.bgColor,
    required this.previewColor,
    this.previewPixels,
    this.previewFg = true,
    this.showGrid = false,
  });

  final Uint8List pixels;
  final double pixelSize;
  final Color fgColor;
  final Color bgColor;
  final Color previewColor;
  final List<int>? previewPixels;
  final bool previewFg;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = bgColor,
    );

    // Foreground pixels
    final fgPaint = Paint()..color = fgColor;
    final Set<int> previewSet = previewPixels != null
        ? Set.from(previewPixels!)
        : const {};

    for (int y = 0; y < _kH; y++) {
      for (int x = 0; x < _kW; x++) {
        final idx = y * _kW + x;
        bool draw;
        if (previewSet.contains(idx)) {
          draw = previewFg;
        } else {
          draw = pixels[idx] != 0;
        }
        if (draw) {
          canvas.drawRect(
            Rect.fromLTWH(x * pixelSize, y * pixelSize, pixelSize, pixelSize),
            fgPaint,
          );
        }
      }
    }

    // Preview pixels with accent color
    if (previewPixels != null && previewPixels!.isNotEmpty) {
      final previewPaint = Paint()
        ..color = previewColor.withAlpha(180);
      for (final idx in previewPixels!) {
        final px = idx % _kW;
        final py = idx ~/ _kW;
        canvas.drawRect(
          Rect.fromLTWH(
            px * pixelSize,
            py * pixelSize,
            pixelSize,
            pixelSize,
          ),
          previewPaint,
        );
      }
    }

    // Grid
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.black.withAlpha(30)
        ..strokeWidth = 0.5;
      for (int x = 0; x <= _kW; x++) {
        canvas.drawLine(
          Offset(x * pixelSize, 0),
          Offset(x * pixelSize, _kH * pixelSize),
          gridPaint,
        );
      }
      for (int y = 0; y <= _kH; y++) {
        canvas.drawLine(
          Offset(0, y * pixelSize),
          Offset(_kW * pixelSize, y * pixelSize),
          gridPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.pixels != pixels ||
      old.previewPixels != previewPixels ||
      old.pixelSize != pixelSize ||
      old.showGrid != showGrid;
}

class _ThumbnailPainter extends CustomPainter {
  const _ThumbnailPainter({
    required this.pixels,
    required this.fgColor,
    required this.bgColor,
  });

  final Uint8List pixels;
  final Color fgColor;
  final Color bgColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);
    final pw = size.width / _kW;
    final ph = size.height / _kH;
    final fgPaint = Paint()..color = fgColor;
    for (int y = 0; y < _kH; y++) {
      for (int x = 0; x < _kW; x++) {
        if (pixels[y * _kW + x] != 0) {
          canvas.drawRect(
            Rect.fromLTWH(x * pw, y * ph, pw, ph),
            fgPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      old.pixels != old.pixels || old.fgColor != fgColor;
}

// ── Reusable UI widgets ───────────────────────────────────────────────────────

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
    required this.label,
    required this.colors,
    required this.onTap,
    this.iconTransform,
    this.tooltip,
  });

  final IconData icon;
  final String label;
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
                    child: Icon(
                      icon,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: colors.textSecondary,
                  ),
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
        height: 40,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
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
