import 'dart:typed_data';

import 'package:flipperlib/api/http_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHeaderBlock', () {
    test('parses CRLF separated headers', () {
      final headers = parseHeaderBlock(
        'Content-Type: application/json\r\nAccept: */*\r\n',
      );
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Accept'], '*/*');
      expect(headers.length, 2);
    });

    test('parses LF separated headers and trims whitespace', () {
      final headers = parseHeaderBlock('X-Token:   abc123  \nHost: example.com');
      expect(headers['X-Token'], 'abc123');
      expect(headers['Host'], 'example.com');
    });

    test('keeps colons inside the value', () {
      final headers = parseHeaderBlock('X-Time: 12:30:00');
      expect(headers['X-Time'], '12:30:00');
    });

    test('skips blank and malformed lines', () {
      final headers = parseHeaderBlock('\r\nGarbage\r\n: novalue\r\nA: b');
      expect(headers, {'A': 'b'});
    });

    test('empty input yields empty map', () {
      expect(parseHeaderBlock(''), isEmpty);
    });
  });

  group('formatHeaderBlock', () {
    test('serializes to CRLF terminated lines', () {
      final raw = formatHeaderBlock({'A': '1', 'B': '2'});
      expect(raw, 'A: 1\r\nB: 2\r\n');
    });

    test('round-trips through parseHeaderBlock', () {
      const original = {'Content-Type': 'text/plain', 'X-Id': '42'};
      expect(parseHeaderBlock(formatHeaderBlock(original)), original);
    });
  });

  group('chunkByteViews', () {
    Uint8List bytes(List<int> values) => Uint8List.fromList(values);

    test('splits evenly divisible data', () {
      final chunks = chunkByteViews(bytes([1, 2, 3, 4]), 2).toList();
      expect(chunks, [
        [1, 2],
        [3, 4],
      ]);
    });

    test('keeps the remainder in a final smaller chunk', () {
      final chunks = chunkByteViews(bytes([1, 2, 3, 4, 5]), 2).toList();
      expect(chunks, [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('returns whole input when chunk size is non-positive', () {
      expect(chunkByteViews(bytes([1, 2, 3]), 0).toList(), [
        [1, 2, 3],
      ]);
    });

    test('returns the whole input as a single chunk when it fits', () {
      final chunks = chunkByteViews(bytes([1, 2, 3]), 8).toList();
      expect(chunks, [
        [1, 2, 3],
      ]);
    });

    test('yields zero-copy views into the source buffer', () {
      final source = bytes([1, 2, 3, 4]);
      final chunks = chunkByteViews(source, 2).toList();
      source[2] = 9;
      expect(chunks[1], [9, 4]);
    });

    test('yields nothing for empty input', () {
      expect(chunkByteViews(bytes([]), 4).toList(), isEmpty);
    });
  });
}
