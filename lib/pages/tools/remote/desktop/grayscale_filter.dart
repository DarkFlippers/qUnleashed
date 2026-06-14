import 'dart:typed_data';

/// Recovers grayscale shades from the Flipper's 1-bit screen stream.
///
/// Apps like *arddrivin* fake gray on the monochrome display by flickering a
/// pixel on/off every frame (`GRAY = alternate lit/unlit`). A single captured
/// frame therefore shows a checkerboard; averaging consecutive frames recovers
/// the intended shade. With [depth] == 2 a flickering pixel lands exactly on
/// the midpoint → 3 colors (background / gray / foreground), which matches
/// arddrivin's two-frame alternation. A larger [depth] yields more shades
/// (the *ardens* approach) at the cost of extra motion blur.
///
/// Frames are pushed unconditionally so the history stays warm and toggling the
/// filter on is instant; rendering only blends when the caller asks for it.
class GrayscaleFilter {
  GrayscaleFilter({this.depth = 2});

  /// Number of frames averaged together. 2 ⇒ three colors.
  int depth;

  final List<Uint8List> _history = [];

  void reset() => _history.clear();

  /// Records a frame's 0/1 pixel indices (128×64, foreground = 1).
  void push(Uint8List pixelIndices) {
    _history.add(pixelIndices);
    while (_history.length > depth) {
      _history.removeAt(0);
    }
  }

  /// Builds an RGBA buffer where each pixel is the temporal average of the
  /// retained frames, lerped between [bgColor] (always off) and [fgColor]
  /// (always on). Colors are ARGB 0xAARRGGBB.
  Uint8List render(int pixelCount, int bgColor, int fgColor) {
    final out = Uint8List(pixelCount * 4);
    final n = _history.length;
    if (n == 0) return out;

    final bgR = (bgColor >> 16) & 0xFF;
    final bgG = (bgColor >> 8) & 0xFF;
    final bgB = bgColor & 0xFF;
    final dR = ((fgColor >> 16) & 0xFF) - bgR;
    final dG = ((fgColor >> 8) & 0xFF) - bgG;
    final dB = (fgColor & 0xFF) - bgB;
    final alpha = (bgColor >> 24) & 0xFF;

    for (var i = 0; i < pixelCount; i++) {
      var sum = 0;
      for (var h = 0; h < n; h++) {
        sum += _history[h][i];
      }
      final pi = i * 4;
      out[pi] = bgR + dR * sum ~/ n;
      out[pi + 1] = bgG + dG * sum ~/ n;
      out[pi + 2] = bgB + dB * sum ~/ n;
      out[pi + 3] = alpha;
    }
    return out;
  }
}
