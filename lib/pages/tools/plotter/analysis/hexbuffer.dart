class Hexbuffer {
  Hexbuffer([String line = '']) : line = line.replaceAll(RegExp(r'\s'), '');

  String line;

  static String _dec2hex(num value, [int width = 2]) {
    final mask = (1 << (4 * width)) - 1;
    final v = value.round() & mask;
    return v.toRadixString(16).toUpperCase().padLeft(width, '0');
  }

  void pushNibble(num value) {
    line += _dec2hex(value, 1);
  }

  void pushByte(num value) {
    line += _dec2hex(value, 2);
  }

  void pushWord(num value) {
    line += _dec2hex(value, 4);
  }
}
