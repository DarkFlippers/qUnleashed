import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/cuid_dict_format.dart';

void main() {
  group('formatCuidDictEntry', () {
    // The on-device reader sizes a CUID entry at sizeof(MfClassicKey) + 1 and
    // drops every line that is not exactly that wide, so a 12-digit key makes
    // the whole dictionary read as empty. These pin the 14-digit layout.
    test('is a 2-digit key index followed by the 12-digit key', () {
      final entry = formatCuidDictEntry(
        sector: 0,
        isKeyA: true,
        key: 0xA0A1A2A3A4A5,
      );
      expect(entry, '00A0A1A2A3A4A5');
      expect(entry, hasLength(14));
    });

    test('key B of a sector sits one index above key A', () {
      expect(
        formatCuidDictEntry(sector: 3, isKeyA: true, key: 0x112233445566),
        startsWith('06'),
      );
      expect(
        formatCuidDictEntry(sector: 3, isKeyA: false, key: 0x112233445566),
        startsWith('07'),
      );
    });

    test('the highest MIFARE Classic 4K index still fits one byte', () {
      // Sector 39 key B - the last index a 4K card's dictionary walk reaches.
      expect(
        formatCuidDictEntry(sector: 39, isKeyA: false, key: 0xFFFFFFFFFFFF),
        '4FFFFFFFFFFFFF',
      );
    });

    test('an index or key too wide for the entry asserts (a caller bug)', () {
      // Either would widen the line past 14, and the on-device reader truncates
      // an over-wide line onto an unrelated key index instead of dropping it.
      // Only the width is this function's to guard - that a card has no sector
      // 40 is the parser's rule, and sector 40 still renders a valid entry.
      expect(
        formatCuidDictEntry(sector: 40, isKeyA: true, key: 0x1),
        '50000000000001',
      );
      expect(
        () => formatCuidDictEntry(sector: 128, isKeyA: true, key: 0x1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => formatCuidDictEntry(sector: -1, isKeyA: true, key: 0x1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () =>
            formatCuidDictEntry(sector: 0, isKeyA: true, key: 0x1FFFFFFFFFFFF),
        throwsA(isA<AssertionError>()),
      );
    });

    test('pads a short key to the full width', () {
      expect(
        formatCuidDictEntry(sector: 10, isKeyA: true, key: 0x1),
        '14000000000001',
      );
    });
  });

  group('writeCuidDictEntry', () {
    test('writes 15 bytes at an offset: the entry plus its newline', () {
      // How the isolate uses it - entries packed back to back into one chunk.
      final out = Uint8List(2 * cuidDictEntryBytes);
      writeCuidDictEntry(out, 0, sector: 0, isKeyA: true, key: 0xA0A1A2A3A4A5);
      writeCuidDictEntry(
        out,
        cuidDictEntryBytes,
        sector: 3,
        isKeyA: false,
        key: 0x112233445566,
      );
      expect(String.fromCharCodes(out, 0, 14), '00A0A1A2A3A4A5');
      expect(out[14], 0x0A);
      expect(String.fromCharCodes(out, 15, 29), '07112233445566');
      expect(out[29], 0x0A);
    });
  });
}
