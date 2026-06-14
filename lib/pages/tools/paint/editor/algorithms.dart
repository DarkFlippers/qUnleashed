import 'dart:math' as math;

List<(int, int)> bresenham(int x0, int y0, int x1, int y1) {
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

List<(int, int)> rectOutline(int x0, int y0, int x1, int y1) {
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

List<(int, int)> ellipsePoints(int cx, int cy, int rx, int ry) {
  final pts = <(int, int)>{};
  if (rx == 0 && ry == 0) return [(cx, cy)];

  int x = 0;
  int y = ry;
  final rx2 = rx * rx;
  final ry2 = ry * ry;
  int p = ry2 - rx2 * ry + (rx2 ~/ 4);

  void add4(int px, int py) {
    pts.add((cx + px, cy + py));
    pts.add((cx - px, cy + py));
    pts.add((cx + px, cy - py));
    pts.add((cx - px, cy - py));
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
