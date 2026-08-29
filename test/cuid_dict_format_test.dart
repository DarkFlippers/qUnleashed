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

    test('an index or key too wide for the entry is refused', () {
      // Either would widen the line past 14, and the on-device reader truncates
      // an over-wide line onto an unrelated key index instead of dropping it -
      // so this throws in release builds too rather than writing a bad entry.
      // Only the width is this function's to guard: that a card has no sector
      // 40 is the parser's rule, and sector 40 still renders a valid entry.
      expect(
        formatCuidDictEntry(sector: 40, isKeyA: true, key: 0x1),
        '50000000000001',
      );
      expect(
        () => formatCuidDictEntry(sector: 128, isKeyA: true, key: 0x1),
        throwsArgumentError,
      );
      expect(
        () => formatCuidDictEntry(sector: -1, isKeyA: true, key: 0x1),
        throwsArgumentError,
      );
      expect(
        () =>
            formatCuidDictEntry(sector: 0, isKeyA: true, key: 0x1FFFFFFFFFFFF),
        throwsArgumentError,
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

  group('CuidDictBuilder', () {
    // The builder is what turns per-sector-key candidate batches into the body
    // written to the device. Its job is that each candidate stays filed under
    // the key index of the sector key it was recovered for - merging them, as
    // an earlier version did, makes the device try none of them.
    test('files each batch under its own sector key, in the order added', () {
      final body =
          (CuidDictBuilder()
                ..add(
                  sector: 3,
                  isKeyA: true,
                  keys: Uint64List.fromList([0x111111111111, 0x222222222222]),
                )
                ..add(
                  sector: 3,
                  isKeyA: false,
                  keys: Uint64List.fromList([0x333333333333]),
                )
                ..add(
                  sector: 7,
                  isKeyA: false,
                  keys: Uint64List.fromList([0x444444444444]),
                ))
              .build();

      expect(body.entries, 4);
      expect(body.bytes, hasLength(4 * cuidDictEntryBytes));
      expect(
        String.fromCharCodes(body.bytes).trimRight().split('\n'),
        // Key A of sector 3 is index 06, key B is 07, key B of sector 7 is 0F.
        [
          '06111111111111',
          '06222222222222',
          '07333333333333',
          '0F444444444444',
        ],
      );
      expect(body.isComplete, isTrue);
      expect(body.isEmpty, isFalse);
    });

    test('records a sector key that yielded no candidates', () {
      // The device indexes by key index and skips an index with no entries, so
      // an empty batch means that sector key is never attacked at all.
      final body =
          (CuidDictBuilder()
                ..add(sector: 1, isKeyA: true, keys: Uint64List(0))
                ..add(
                  sector: 1,
                  isKeyA: false,
                  keys: Uint64List.fromList([0x555555555555]),
                ))
              .build();

      expect(body.entries, 1);
      expect(body.skippedKeys, ['1A']);
      expect(body.isComplete, isFalse);
      expect(body.isEmpty, isFalse);
    });

    test('records a batch that was cut short at the generator cap', () {
      final body =
          (CuidDictBuilder()..add(
                sector: 2,
                isKeyA: true,
                keys: Uint64List.fromList([0x666666666666]),
                atCapacity: true,
              ))
              .build();

      expect(body.cappedKeys, ['2A']);
      expect(body.isComplete, isFalse);
    });

    test('a builder with nothing added is empty, not complete-with-zero', () {
      final body = CuidDictBuilder().build();
      expect(body.isEmpty, isTrue);
      expect(body.bytes, isEmpty);
    });

    test('consumes each batch before returning (reused-buffer safety)', () {
      // The isolate passes a view over a native buffer that the next call
      // overwrites, so add() must read it eagerly. Reusing one list models it.
      final reused = Uint64List.fromList([0x777777777777]);
      final builder = CuidDictBuilder()
        ..add(sector: 0, isKeyA: true, keys: reused);
      reused[0] = 0x888888888888;
      builder.add(sector: 0, isKeyA: false, keys: reused);

      expect(
        String.fromCharCodes(builder.build().bytes).trimRight().split('\n'),
        ['00777777777777', '01888888888888'],
      );
    });
  });
}
