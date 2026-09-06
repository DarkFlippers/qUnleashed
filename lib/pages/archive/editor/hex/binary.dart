import 'dart:convert';

const int _kSampleSize = 8192;
const double _kControlRatio = 0.03;

/// Tells whether the bytes would come out as garbage in the text editor, so
/// the page can open them in the hex table instead.
bool looksBinary(List<int> bytes) {
  if (bytes.isEmpty) return false;
  if (_hasWideBom(bytes)) return true;
  final truncated = bytes.length > _kSampleSize;
  final sample = truncated ? bytes.sublist(0, _kSampleSize) : bytes;
  var control = 0;
  for (final byte in sample) {
    if (byte == 0x00) return true;
    if (byte == 0x7f || (byte < 0x20 && !_isTextControl(byte))) control++;
  }
  if (control > sample.length * _kControlRatio) return true;
  return !_isUtf8(truncated ? _dropPartialSequence(sample) : sample);
}

bool _isTextControl(int byte) =>
    byte == 0x09 ||
    byte == 0x0a ||
    byte == 0x0b ||
    byte == 0x0c ||
    byte == 0x0d ||
    byte == 0x1b;

bool _hasWideBom(List<int> bytes) {
  if (bytes.length >= 2) {
    final head = (bytes[0] << 8) | bytes[1];
    if (head == 0xfffe || head == 0xfeff) return true;
  }
  return false;
}

bool _isUtf8(List<int> bytes) {
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

/// Cuts a multi-byte sequence the sample may have split in half, so a valid
/// file is not called binary because of where the sample ends.
List<int> _dropPartialSequence(List<int> sample) {
  var end = sample.length;
  for (var back = 0; back < 4 && end > 0; back++) {
    final byte = sample[end - 1];
    if (byte < 0x80) return sample.sublist(0, end);
    if (byte >= 0xc0) return sample.sublist(0, end - 1);
    end--;
  }
  return sample.sublist(0, end);
}
