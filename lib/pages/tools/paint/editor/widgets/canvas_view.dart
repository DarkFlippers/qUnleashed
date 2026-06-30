import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../theme/colors/display.dart';
import '../../../../../theme/theme.dart';
import '../../constants.dart';
import '../controller.dart';
import '../painters.dart';

/// The drawing surface. Owns all of its own pan/zoom interaction state so the
/// editor page no longer has to juggle pointer bookkeeping. Drawing strokes are
/// forwarded to [ctrl]; right-mouse drag, scroll wheel, trackpad and two-finger
/// touch all pan, clamped to the zoomed canvas bounds.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.ctrl});

  final PaintController ctrl;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  PaintController get _ctrl => widget.ctrl;

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

  ({double x, double y}) _maxPan(Size cs) {
    final ps = _ctrl.effectivePixelSize(cs.width);
    final maxX = ((kCanvasWidth * ps - cs.width) / 2).clamp(0.0, double.infinity);
    final maxY = ((kCanvasHeight * ps - cs.height) / 2).clamp(0.0, double.infinity);
    return (x: maxX, y: maxY);
  }

  void _onScrollPan(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final cs = _canvasContainerSize;
    if (cs == null) return;
    // Always consume so the parent ScrollView never scrolls over the canvas.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      if (event is! PointerScrollEvent) return;
      final m = _maxPan(cs);
      if (m.x == 0 && m.y == 0) return;
      setState(() {
        _panOffset = Offset(
          (_panOffset.dx - event.scrollDelta.dx).clamp(-m.x, m.x),
          (_panOffset.dy - event.scrollDelta.dy).clamp(-m.y, m.y),
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
      final m = _maxPan(cs);
      setState(() {
        _panOffset = Offset(
          (_panStartOffset.dx + e.localPosition.dx - _panStartLocal.dx).clamp(-m.x, m.x),
          (_panStartOffset.dy + e.localPosition.dy - _panStartLocal.dy).clamp(-m.y, m.y),
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
        final m = _maxPan(cs);
        final centroid = _touchCentroid();
        setState(() {
          _panOffset = Offset(
            (_twoFingerStartPanOffset.dx + centroid.dx - _twoFingerStartCentroid.dx).clamp(-m.x, m.x),
            (_twoFingerStartPanOffset.dy + centroid.dy - _twoFingerStartCentroid.dy).clamp(-m.y, m.y),
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
    final m = _maxPan(cs);
    if (m.x == 0 && m.y == 0) return;
    setState(() {
      _panOffset = Offset(
        (_panOffset.dx + e.panDelta.dx).clamp(-m.x, m.x),
        (_panOffset.dy + e.panDelta.dy).clamp(-m.y, m.y),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final display = DisplayColors.forColors(colors);
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
        // Keep the stored offset clamped so a zoom-out (or zoom reset) recenters
        // the canvas automatically without the page tracking pan state.
        _panOffset = Offset(panX, panY);
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
                  color: display.background,
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
                          fgColor: display.foreground,
                          bgColor: display.background,
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
}
