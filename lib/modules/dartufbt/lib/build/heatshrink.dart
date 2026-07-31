import 'dart:typed_data';

class Heatshrink {
  const Heatshrink({this.windowSize = 8, this.lookaheadSize = 4});

  static const int matchNotFound = 0xFFFF;

  final int windowSize;
  final int lookaheadSize;

  int get _window => 1 << windowSize;
  int get _lookahead => 1 << lookaheadSize;

  Uint8List compress(List<int> input) {
    final window = _window;
    final lookahead = _lookahead;
    final buffer = Uint8List(2 * window);
    final out = _BitWriter();

    var pos = 0;
    var inputSize = 0;
    var scanIndex = 0;

    while (true) {
      final room = window - inputSize;
      final take = room < input.length - pos ? room : input.length - pos;
      buffer.setRange(
        window + inputSize,
        window + inputSize + take,
        input,
        pos,
      );
      pos += take;
      inputSize += take;
      final finishing = pos >= input.length;

      var exhausted = false;
      while (!exhausted) {
        final limit = inputSize - (finishing ? 1 : lookahead);
        if (limit < 0 || scanIndex > limit) {
          exhausted = true;
          break;
        }

        final end = window + scanIndex;
        final start = end - window;
        var maxPossible = lookahead;
        if (inputSize - scanIndex < lookahead) {
          maxPossible = inputSize - scanIndex;
        }

        final match = _findLongestMatch(buffer, start, end, maxPossible);
        if (match == null) {
          out.writeBit(1);
          out.writeBits(buffer[end], 8);
          scanIndex++;
        } else {
          out.writeBit(0);
          out.writeBits(match.position - 1, windowSize);
          out.writeBits(match.length - 1, lookaheadSize);
          scanIndex += match.length;
        }
      }

      if (finishing) break;

      final rem = window - scanIndex;
      buffer.setRange(0, window + rem, buffer.sublist(scanIndex));
      inputSize -= scanIndex;
      scanIndex = 0;
    }

    return out.toBytes();
  }

  _Match? _findLongestMatch(Uint8List buffer, int start, int end, int maxLen) {
    var matchMaxLen = 0;
    var matchIndex = matchNotFound;

    for (var pos = end - 1; pos >= start; pos--) {
      if (buffer[pos + matchMaxLen] == buffer[end + matchMaxLen] &&
          buffer[pos] == buffer[end]) {
        var len = 1;
        for (; len < maxLen; len++) {
          if (buffer[pos + len] != buffer[end + len]) break;
        }
        if (len > matchMaxLen) {
          matchMaxLen = len;
          matchIndex = pos;
          if (len == maxLen) break;
        }
      }
    }

    final breakEvenPoint = 1 + windowSize + lookaheadSize;
    if (matchMaxLen > breakEvenPoint ~/ 8) {
      return _Match(end - matchIndex, matchMaxLen);
    }
    return null;
  }

  Uint8List decompress(List<int> input) {
    final window = _window;
    final mask = window - 1;
    final buffer = Uint8List(window);
    final reader = _BitReader(input);
    final out = <int>[];
    var head = 0;

    while (true) {
      final tag = reader.readBits(1);
      if (tag == null) break;

      if (tag == 1) {
        final byte = reader.readBits(8);
        if (byte == null) break;
        buffer[head++ & mask] = byte;
        out.add(byte);
      } else {
        final index = reader.readBits(windowSize);
        if (index == null) break;
        final count = reader.readBits(lookaheadSize);
        if (count == null) break;

        final offset = index + 1;
        for (var i = 0; i <= count; i++) {
          final byte = buffer[(head - offset) & mask];
          buffer[head++ & mask] = byte;
          out.add(byte);
        }
      }
    }
    return Uint8List.fromList(out);
  }
}

class _Match {
  const _Match(this.position, this.length);

  final int position;
  final int length;
}

class _BitWriter {
  final List<int> _bytes = [];
  int _current = 0;
  int _bits = 0;

  void writeBit(int bit) {
    _current = (_current << 1) | (bit & 1);
    _bits++;
    if (_bits == 8) {
      _bytes.add(_current & 0xFF);
      _current = 0;
      _bits = 0;
    }
  }

  void writeBits(int value, int count) {
    for (var i = count - 1; i >= 0; i--) {
      writeBit((value >> i) & 1);
    }
  }

  Uint8List toBytes() {
    if (_bits > 0) {
      _bytes.add((_current << (8 - _bits)) & 0xFF);
      _current = 0;
      _bits = 0;
    }
    return Uint8List.fromList(_bytes);
  }
}

class _BitReader {
  _BitReader(this._input);

  final List<int> _input;
  int _pos = 0;
  int _bit = 0;

  int? readBits(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      if (_pos >= _input.length) return null;
      final bit = (_input[_pos] >> (7 - _bit)) & 1;
      value = (value << 1) | bit;
      _bit++;
      if (_bit == 8) {
        _bit = 0;
        _pos++;
      }
    }
    return value;
  }
}
