import 'dart:math' as math;

import 'package:flutter/foundation.dart';

class PlotController extends ChangeNotifier {
  PlotController({required this.dataWidth});

  final double dataWidth;

  double _viewWidth = 0;
  double _zoom = 1;
  double _left = 0;

  double get zoom => _zoom;
  double get left => _left;
  double get viewWidth => _viewWidth;

  static const double maxZoom = 600;

  bool get canPan => _zoom > 1.0001;

  double get _maxLeft {
    final ml = 1 - 1 / _zoom;
    return ml < 0 ? 0 : ml;
  }

  double get k => _zoom;

  double get tx => -_left * _viewWidth * _zoom;

  double get panFraction {
    final ml = _maxLeft;
    return ml <= 0 ? 0 : (_left / ml).clamp(0.0, 1.0);
  }

  double get zoomFraction =>
      (math.log(_zoom) / math.log(maxZoom)).clamp(0.0, 1.0);

  void setViewWidth(double width) {
    if (width <= 0 || width == _viewWidth) return;
    _viewWidth = width;
    _zoom = _zoom.clamp(1.0, maxZoom);
    _left = _left.clamp(0.0, _maxLeft);
  }

  void _apply(double zoom, double left) {
    final nz = zoom.clamp(1.0, maxZoom);
    final maxLeft = nz <= 1 ? 0.0 : (1 - 1 / nz);
    final nl = left.clamp(0.0, maxLeft);
    if (nz == _zoom && nl == _left) return;
    _zoom = nz;
    _left = nl;
    notifyListeners();
  }

  void zoomAround(double newZoom, double focalFraction) {
    final dataUnderFocal = _left + focalFraction / _zoom;
    final nz = newZoom.clamp(1.0, maxZoom);
    _apply(nz, dataUnderFocal - focalFraction / nz);
  }

  void zoomBy(double factor) => zoomAround(_zoom * factor, 0.5);

  void setZoomFraction(double s) {
    zoomAround(math.pow(maxZoom, s).toDouble(), 0.5);
  }

  void setPanFraction(double p) {
    final ml = _maxLeft;
    if (ml <= 0) return;
    _apply(_zoom, p * ml);
  }

  void panByPixels(double dx) {
    if (_viewWidth <= 0) return;
    _apply(_zoom, _left - (dx / _viewWidth) / _zoom);
  }

  void reset() => _apply(1, 0);
}
