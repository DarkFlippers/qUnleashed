import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_models.dart';

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
      // Sector 39 key B - the last index the firmware can address.
      expect(
        formatCuidDictEntry(sector: 39, isKeyA: false, key: 0xFFFFFFFFFFFF),
        '4FFFFFFFFFFFFF',
      );
    });

    test('pads a short key to the full width', () {
      expect(
        formatCuidDictEntry(sector: 10, isKeyA: true, key: 0x1),
        '14000000000001',
      );
    });
  });
}
