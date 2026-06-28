class Bitbuffer {
  final List<int> bytes = [];
  int len = 0;

  void _ensure(int index) {
    while (bytes.length <= index) {
      bytes.add(0);
    }
  }

  void push(int bit) {
    final value = bit != 0 ? 0x80 : 0;
    final index = len ~/ 8;
    _ensure(index);
    bytes[index] |= value >> (len % 8);
    len += 1;
  }

  void pushZero() => push(0);

  void pushOne() => push(1);

  void pushNibble(int n) {
    for (var j = 3; j >= 0; --j) {
      push((n >> j) & 1);
    }
  }

  void pushByte(int n) {
    for (var j = 7; j >= 0; --j) {
      push((n >> j) & 1);
    }
  }

  void pushBreak() {
    final b = (len + 7) ~/ 8;
    _ensure(b);
    bytes[b] = -1;
    len = (b + 1) * 8;
  }

  String toHexString() {
    var s = '{$len}';
    for (var j = 0; j < len; j += 8) {
      final index = j ~/ 8;
      final b = index < bytes.length ? bytes[index] : 0;
      if (b < 0) {
        s += ' / ';
      } else {
        s += ' ';
        s += (b >> 4).toRadixString(16).toUpperCase();
        if (j + 4 < len) {
          s += (b & 0xf).toRadixString(16).toUpperCase();
        }
      }
    }
    return s;
  }
}
