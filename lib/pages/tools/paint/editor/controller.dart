import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../virtual_display_session.dart';
import 'algorithms.dart';

class PaintController extends ChangeNotifier {
  final List<Uint8List> frames = [Uint8List(kCanvasWidth * kCanvasHeight)];
  int currentFrame = 0;
  int pixelVersion = 0;

  final List<List<Uint8List>> _undoStack = [];
  final List<List<Uint8List>> _redoStack = [];

  DrawTool tool = DrawTool.pencil;
  bool drawFg = true;
  bool showGrid = false;
  int zoomIndex = 1;

  int? strokeStartX, strokeStartY;
  List<int>? previewPixels;
  int? _lastPencilX, _lastPencilY;

  Timer? _playTimer;
  bool isPlaying = false;
  bool showOnionSkin = false;
  bool _playingActive = false;
  int _activeRepeatsDone = 0;

  bool _closing = false;
  int? activePointer;
  Timer? _pushTimer;

  int frameRate = 2;
  int duration = 3600;
  int activeCycles = 1;
  int activeCooldown = 7;
  int passiveFrameCount = -1;
  bool compressBm = false;

  PaintController() {
    VirtualDisplaySession.instance.enterLive();
  }

  Uint8List get currentPixels => frames[currentFrame];

  int get effectivePassiveCount {
    final n = frames.length;
    return passiveFrameCount < 0 ? n : passiveFrameCount.clamp(0, n);
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isClosing => _closing;

  double effectivePixelSize(double containerWidth) {
    return ((containerWidth - kPassivePad * 2) / kCanvasWidth) *
        kZoomLevels[zoomIndex];
  }

  String get zoomLabel {
    final z = kZoomLevels[zoomIndex];
    return z == z.truncateToDouble() ? '${z.toInt()}x' : '${z}x';
  }

  /// Debounced: while a stroke is in progress the timer keeps resetting, so the
  /// device only updates once the pixels settle (drawing stops).
  void schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 100), () {
      VirtualDisplaySession.instance.pushFrame(currentPixels);
    });
  }

  void pushUndo() {
    _undoStack.add(frames.map((f) => Uint8List.fromList(f)).toList());
    if (_undoStack.length > kMaxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(frames.map((f) => Uint8List.fromList(f)).toList());
    final prev = _undoStack.removeLast();
    frames
      ..clear()
      ..addAll(prev);
    currentFrame = currentFrame.clamp(0, frames.length - 1);
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(frames.map((f) => Uint8List.fromList(f)).toList());
    final next = _redoStack.removeLast();
    frames
      ..clear()
      ..addAll(next);
    currentFrame = currentFrame.clamp(0, frames.length - 1);
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void setPixel(int x, int y, bool fg, [Uint8List? target]) {
    if (x < 0 || x >= kCanvasWidth || y < 0 || y >= kCanvasHeight) return;
    (target ?? currentPixels)[y * kCanvasWidth + x] = fg ? 1 : 0;
  }

  void _drawLine(int x0, int y0, int x1, int y1, bool fg, [Uint8List? target]) {
    for (final p in bresenham(x0, y0, x1, y1)) {
      setPixel(p.$1, p.$2, fg, target);
    }
  }

  void _drawRect(int x0, int y0, int x1, int y1, bool fg, [Uint8List? target]) {
    for (final p in rectOutline(x0, y0, x1, y1)) {
      setPixel(p.$1, p.$2, fg, target);
    }
  }

  void _drawEllipse(
    int cx,
    int cy,
    int rx,
    int ry,
    bool fg, [
    Uint8List? target,
  ]) {
    if (rx <= 0 || ry <= 0) {
      setPixel(cx, cy, fg, target);
      return;
    }
    for (final p in ellipsePoints(cx, cy, rx, ry)) {
      setPixel(p.$1, p.$2, fg, target);
    }
  }

  void _floodFill(int x, int y, bool fg) {
    final target = currentPixels[y * kCanvasWidth + x];
    final fill = fg ? 1 : 0;
    if (target == fill) return;
    final queue = <int>[y * kCanvasWidth + x];
    final visited = Uint8List(kCanvasWidth * kCanvasHeight);
    visited[y * kCanvasWidth + x] = 1;
    while (queue.isNotEmpty) {
      final idx = queue.removeLast();
      currentPixels[idx] = fill;
      final px = idx % kCanvasWidth;
      final py = idx ~/ kCanvasWidth;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = px + d.$1;
        final ny = py + d.$2;
        if (nx < 0 ||
            nx >= kCanvasWidth ||
            ny < 0 ||
            ny >= kCanvasHeight) {
          continue;
        }
        final ni = ny * kCanvasWidth + nx;
        if (visited[ni] != 0 || currentPixels[ni] != target) continue;
        visited[ni] = 1;
        queue.add(ni);
      }
    }
  }

  List<int> buildPreview(int x0, int y0, int x1, int y1) {
    final preview = <int>[];
    List<(int, int)> pts;
    switch (tool) {
      case DrawTool.line:
        pts = bresenham(x0, y0, x1, y1);
      case DrawTool.rect:
        pts = rectOutline(x0, y0, x1, y1);
      case DrawTool.ellipse:
        final rx = (x1 - x0).abs() ~/ 2;
        final ry = (y1 - y0).abs() ~/ 2;
        final cx = math.min(x0, x1) + rx;
        final cy = math.min(y0, y1) + ry;
        pts = ellipsePoints(cx, cy, rx, ry);
      default:
        return [];
    }
    for (final p in pts) {
      if (p.$1 >= 0 &&
          p.$1 < kCanvasWidth &&
          p.$2 >= 0 &&
          p.$2 < kCanvasHeight) {
        preview.add(p.$2 * kCanvasWidth + p.$1);
      }
    }
    return preview;
  }

  void _commitPreview(int x1, int y1) {
    final x0 = strokeStartX;
    final y0 = strokeStartY;
    if (x0 == null || y0 == null) return;
    switch (tool) {
      case DrawTool.line:
        _drawLine(x0, y0, x1, y1, drawFg);
      case DrawTool.rect:
        _drawRect(x0, y0, x1, y1, drawFg);
      case DrawTool.ellipse:
        final rx = (x1 - x0).abs() ~/ 2;
        final ry = (y1 - y0).abs() ~/ 2;
        final cx = math.min(x0, x1) + rx;
        final cy = math.min(y0, y1) + ry;
        _drawEllipse(cx, cy, rx, ry, drawFg);
      default:
        break;
    }
  }

  void onPointerDown(int x, int y, int pointer) {
    if (activePointer != null) return;
    activePointer = pointer;
    switch (tool) {
      case DrawTool.pencil:
      case DrawTool.eraser:
        pushUndo();
        setPixel(x, y, tool == DrawTool.pencil ? drawFg : !drawFg);
        _lastPencilX = x;
        _lastPencilY = y;
        pixelVersion++;
        schedulePush();
        notifyListeners();
      case DrawTool.fill:
        pushUndo();
        _floodFill(x, y, drawFg);
        pixelVersion++;
        schedulePush();
        notifyListeners();
      case DrawTool.line:
      case DrawTool.rect:
      case DrawTool.ellipse:
        strokeStartX = x;
        strokeStartY = y;
        previewPixels = [];
        notifyListeners();
    }
  }

  void onPointerMove(int x, int y, int pointer) {
    if (pointer != activePointer) return;
    switch (tool) {
      case DrawTool.pencil:
      case DrawTool.eraser:
        final lx = _lastPencilX;
        final ly = _lastPencilY;
        if (lx != null && ly != null && (lx != x || ly != y)) {
          for (final p in bresenham(lx, ly, x, y)) {
            setPixel(p.$1, p.$2, tool == DrawTool.pencil ? drawFg : !drawFg);
          }
        }
        _lastPencilX = x;
        _lastPencilY = y;
        pixelVersion++;
        schedulePush();
        notifyListeners();
      case DrawTool.fill:
        break;
      case DrawTool.line:
      case DrawTool.rect:
      case DrawTool.ellipse:
        final x0 = strokeStartX;
        final y0 = strokeStartY;
        if (x0 == null || y0 == null) return;
        previewPixels = buildPreview(x0, y0, x, y);
        notifyListeners();
    }
  }

  void onPointerUp(int x, int y, int pointer) {
    if (pointer != activePointer) return;
    activePointer = null;
    switch (tool) {
      case DrawTool.pencil:
      case DrawTool.eraser:
      case DrawTool.fill:
        _lastPencilX = null;
        _lastPencilY = null;
      case DrawTool.line:
      case DrawTool.rect:
      case DrawTool.ellipse:
        pushUndo();
        _commitPreview(x, y);
        strokeStartX = null;
        strokeStartY = null;
        previewPixels = null;
        pixelVersion++;
        schedulePush();
        notifyListeners();
    }
  }

  void flipH() {
    pushUndo();
    final p = currentPixels;
    for (int y = 0; y < kCanvasHeight; y++) {
      for (int x = 0; x < kCanvasWidth ~/ 2; x++) {
        final a = y * kCanvasWidth + x;
        final b = y * kCanvasWidth + (kCanvasWidth - 1 - x);
        final tmp = p[a];
        p[a] = p[b];
        p[b] = tmp;
      }
    }
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void flipV() {
    pushUndo();
    final p = currentPixels;
    for (int y = 0; y < kCanvasHeight ~/ 2; y++) {
      for (int x = 0; x < kCanvasWidth; x++) {
        final a = y * kCanvasWidth + x;
        final b = (kCanvasHeight - 1 - y) * kCanvasWidth + x;
        final tmp = p[a];
        p[a] = p[b];
        p[b] = tmp;
      }
    }
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void invert() {
    pushUndo();
    final p = currentPixels;
    for (int i = 0; i < p.length; i++) {
      p[i] = p[i] == 0 ? 1 : 0;
    }
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void clearFrame() {
    pushUndo();
    currentPixels.fillRange(0, currentPixels.length, 0);
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void addFrame() {
    pushUndo();
    frames.insert(currentFrame + 1, Uint8List(kCanvasWidth * kCanvasHeight));
    currentFrame++;
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void duplicateFrame() {
    pushUndo();
    frames.insert(currentFrame + 1, Uint8List.fromList(frames[currentFrame]));
    currentFrame++;
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void deleteFrame() {
    if (frames.length <= 1) {
      clearFrame();
      return;
    }
    pushUndo();
    frames.removeAt(currentFrame);
    currentFrame = currentFrame.clamp(0, frames.length - 1);
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void selectFrame(int idx) {
    if (idx == currentFrame) return;
    isPlaying = false;
    _playTimer?.cancel();
    currentFrame = idx;
    schedulePush();
    notifyListeners();
  }

  void togglePlay() {
    if (isPlaying) {
      isPlaying = false;
      _playingActive = false;
      _activeRepeatsDone = 0;
      _playTimer?.cancel();
    } else {
      isPlaying = true;
      _playingActive = false;
      _activeRepeatsDone = 0;
      _startPlayTimer();
    }
    notifyListeners();
  }

  void _startPlayTimer() {
    _playTimer?.cancel();
    final delayMs = (1000 / frameRate).round().clamp(33, 10000);
    _playTimer = Timer.periodic(
      Duration(milliseconds: delayMs),
      (_) => _onPlayTick(),
    );
  }

  void _onPlayTick() {
    final n = frames.length;
    final passiveN = effectivePassiveCount;
    final activeStart = passiveN;

    if (!_playingActive) {
      if (passiveN == 0) {
        if (n > 0) {
          _playingActive = true;
          currentFrame = 0;
        }
      } else {
        currentFrame = (currentFrame + 1) % passiveN;
      }
    } else {
      final activeEnd = n - 1;
      if (activeStart > activeEnd) {
        _playingActive = false;
        _activeRepeatsDone = 0;
        currentFrame = 0;
      } else {
        final next = currentFrame + 1;
        if (next > activeEnd) {
          _activeRepeatsDone++;
          if (_activeRepeatsDone >= activeCycles) {
            _playingActive = false;
            _activeRepeatsDone = 0;
            currentFrame = passiveN > 0 ? 0 : activeStart;
          } else {
            currentFrame = activeStart;
          }
        } else {
          currentFrame = next;
        }
      }
    }
    schedulePush();
    notifyListeners();
  }

  void triggerActive() {
    final passiveN = effectivePassiveCount;
    if (passiveN >= frames.length) return;
    _playingActive = true;
    _activeRepeatsDone = 0;
    currentFrame = passiveN;
    if (isPlaying) _startPlayTimer();
    notifyListeners();
  }

  void zoomIn() {
    if (zoomIndex < kZoomLevels.length - 1) {
      zoomIndex++;
      notifyListeners();
    }
  }

  void zoomOut() {
    if (zoomIndex > 0) {
      zoomIndex--;
      notifyListeners();
    }
  }

  void zoomReset() {
    zoomIndex = 1;
    notifyListeners();
  }

  void reorderFrame(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    pushUndo();
    final frame = frames.removeAt(oldIndex);
    frames.insert(newIndex, frame);
    if (currentFrame == oldIndex) {
      currentFrame = newIndex;
    } else if (oldIndex < newIndex) {
      if (currentFrame > oldIndex && currentFrame <= newIndex) currentFrame--;
    } else {
      if (currentFrame >= newIndex && currentFrame < oldIndex) currentFrame++;
    }
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void importFramesFromPixels(
    List<Uint8List> newFrames, {
    int? fr,
    int? dur,
    int? ac,
    int? acd,
    int? pfc,
  }) {
    pushUndo();
    frames
      ..clear()
      ..addAll(newFrames);
    currentFrame = 0;
    if (fr != null) frameRate = fr;
    if (dur != null) duration = dur;
    if (ac != null) activeCycles = ac;
    if (acd != null) activeCooldown = acd;
    if (pfc != null) passiveFrameCount = pfc;
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void importSinglePixelFrame(Uint8List pixels) {
    pushUndo();
    final currentIsEmpty = currentPixels.every((pixel) => pixel == 0);
    if (currentIsEmpty) {
      frames[currentFrame] = pixels;
    } else {
      frames.add(pixels);
      currentFrame = frames.length - 1;
    }
    pixelVersion++;
    schedulePush();
    notifyListeners();
  }

  void setTool(DrawTool t) {
    tool = t;
    notifyListeners();
  }

  void setDrawFg(bool v) {
    drawFg = v;
    notifyListeners();
  }

  void setShowGrid(bool v) {
    showGrid = v;
    notifyListeners();
  }

  void setShowOnionSkin(bool v) {
    showOnionSkin = v;
    notifyListeners();
  }

  void setFrameRate(int v) {
    frameRate = v;
    if (isPlaying) _startPlayTimer();
    notifyListeners();
  }

  void setDuration(int v) {
    duration = v;
    notifyListeners();
  }

  void setActiveCycles(int v) {
    activeCycles = v;
    notifyListeners();
  }

  void setActiveCooldown(int v) {
    activeCooldown = v;
    notifyListeners();
  }

  void setPassiveFrameCount(int v) {
    passiveFrameCount = v;
    notifyListeners();
  }

  void setCompressBm(bool v) {
    compressBm = v;
    notifyListeners();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _playTimer?.cancel();
    _pushTimer?.cancel();
    VirtualDisplaySession.instance.leaveLive();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _pushTimer?.cancel();
    if (!_closing) VirtualDisplaySession.instance.leaveLive();
    super.dispose();
  }
}
