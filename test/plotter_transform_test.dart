import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/plotter/plot_controller.dart';

double _screenX({
  required double dataPos,
  required double dataWidth,
  required double width,
  required double zoom,
  required double left,
}) {
  final maxZoom = dataWidth / width;
  final sf = zoom / maxZoom;
  final tx = -left * width * zoom;
  return dataPos * sf + tx;
}

void main() {
  const dataWidth = 200000.0;
  const width = 520.0;

  test('window maps to [0, width] at every zoom level', () {
    final c = PlotController(dataWidth: dataWidth);
    c.setViewWidth(width);

    for (final target in [1.0, 10.0, 50.0, 200.0, 500.0]) {
      while (c.zoom < target && c.zoom < PlotController.maxZoom) {
        c.zoomBy(1.6);
      }
      c.setPanFraction(0.5);

      final windowStart = c.left * dataWidth;
      final windowEnd = (c.left + 1 / c.zoom) * dataWidth;

      final xStart = _screenX(
        dataPos: windowStart,
        dataWidth: dataWidth,
        width: width,
        zoom: c.zoom,
        left: c.left,
      );
      final xEnd = _screenX(
        dataPos: windowEnd,
        dataWidth: dataWidth,
        width: width,
        zoom: c.zoom,
        left: c.left,
      );

      expect(xStart, closeTo(0, 1e-6), reason: 'start off-screen at z=${c.zoom}');
      expect(xEnd, closeTo(width, 1e-6), reason: 'end off-screen at z=${c.zoom}');
    }
  });

  test('left stays within valid pan bounds', () {
    final c = PlotController(dataWidth: dataWidth);
    c.setViewWidth(width);
    c.zoomBy(1.6);
    c.zoomBy(1.6);

    c.setPanFraction(5);
    expect(c.left, lessThanOrEqualTo(1 - 1 / c.zoom + 1e-9));
    c.setPanFraction(-5);
    expect(c.left, greaterThanOrEqualTo(-1e-9));
  });

  test('zoom is never locked and is capped at 600', () {
    final c = PlotController(dataWidth: dataWidth);
    c.setViewWidth(width);
    c.reset();
    expect(c.zoom, 1.0);
    c.zoomBy(1.6);
    expect(c.zoom, greaterThan(1.0), reason: 'zoom locked after reset');
    for (var i = 0; i < 60; i++) {
      c.zoomBy(1.6);
    }
    expect(c.zoom, closeTo(PlotController.maxZoom, 1e-6));
  });

  test('zoom works even when the signal is shorter than the canvas', () {
    final c = PlotController(dataWidth: 100);
    c.setViewWidth(500);
    c.zoomBy(1.6);
    expect(c.zoom, greaterThan(1.0));
  });

  test('reset returns to full view', () {
    final c = PlotController(dataWidth: dataWidth);
    c.setViewWidth(width);
    c.zoomBy(1.6);
    c.setPanFraction(0.8);
    c.reset();
    expect(c.zoom, 1.0);
    expect(c.left, 0.0);
  });

  test('shrinking the view re-clamps without leaving the signal blank', () {
    final c = PlotController(dataWidth: dataWidth);
    c.setViewWidth(width);
    while (c.zoom < 400 && c.zoom < PlotController.maxZoom) {
      c.zoomBy(1.6);
    }
    c.setPanFraction(1.0);
    c.setViewWidth(120);
    expect(c.zoom, lessThanOrEqualTo(PlotController.maxZoom + 1e-9));
    expect(c.left, inInclusiveRange(0.0, 1 - 1 / c.zoom + 1e-9));
  });
}
