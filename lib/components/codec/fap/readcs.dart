import 'dart:typed_data';
import 'dart:convert';

String? readCString(Uint8List bytes, int offset) {
  if (offset < 0 || offset >= bytes.length) return null;
  var end = offset;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }
  return ascii.decode(bytes.sublist(offset, end), allowInvalid: true);
}