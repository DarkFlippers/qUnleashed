const int kCanvasWidth = 128;
const int kCanvasHeight = 64;
const int kMaxUndo = 20;
const int kAnimFrameDelay = 200;
const double kPassivePad = 12.0;
const List<double> kZoomLevels = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0];

enum DrawTool { pencil, eraser, fill, line, rect, ellipse }
