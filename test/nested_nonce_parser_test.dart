import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/nested_models.dart';
import 'package:qunleashed/pages/tools/mifare/nested_nonce_parser.dart';

void main() {
  group('NestedNonceParser', () {
    test('parses a two-sample weak-nested line', () {
      const line =
          'Sec 10 key A cuid 7c30d979 nt0 214904f0 ks0 c03823d1 par0 0000 '
          'nt1 f69baa3a ks1 8a2107ad par1 1010 dist 0';

      final nonces = NestedNonceParser.parse(line);
      expect(nonces, hasLength(1));

      final nonce = nonces.single;
      expect(nonce.sector, 10);
      expect(nonce.keyType, NestedKeyType.a);
      expect(nonce.cuid, 0x7c30d979);
      expect(nonce.dist, 0);
      expect(nonce.hasPair, isTrue);
      expect(nonce.kind, NestedAttackKind.weakNested);

      expect(nonce.samples[0].nt, 0x214904f0);
      expect(nonce.samples[0].ks, 0xc03823d1);
      expect(nonce.samples[0].par, 0); // "0000"
      expect(nonce.samples[1].nt, 0xf69baa3a);
      expect(nonce.samples[1].ks, 0x8a2107ad);
      expect(nonce.samples[1].par, 10); // "1010"
    });

    test('parses a single-sample static-encrypted line', () {
      const line =
          'Sec 0 key B cuid 5bcbb2e4 nt0 940c4716 ks0 bd42bb91 par0 1111 dist 0';

      final nonce = NestedNonceParser.parse(line).single;
      expect(nonce.sector, 0);
      expect(nonce.keyType, NestedKeyType.b);
      expect(nonce.cuid, 0x5bcbb2e4);
      expect(nonce.hasPair, isFalse);
      expect(nonce.kind, NestedAttackKind.staticEncrypted);
      expect(nonce.samples, hasLength(1));
      expect(nonce.samples[0].nt, 0x940c4716);
      expect(nonce.samples[0].ks, 0xbd42bb91);
      expect(nonce.samples[0].par, 15); // "1111"
    });

    test('parses a mixed file and skips blank lines', () {
      const file = '''
Sec 10 key A cuid 7c30d979 nt0 214904f0 ks0 c03823d1 par0 0000 nt1 f69baa3a ks1 8a2107ad par1 1010 dist 0

Sec 0 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
Sec 1 key B cuid 5bcbb2e4 nt0 d7707ed1 ks0 65bc542b par0 0110 dist 0
''';

      final nonces = NestedNonceParser.parse(file);
      expect(nonces, hasLength(3));
      expect(nonces.where((n) => n.hasPair), hasLength(1));
      expect(
        nonces.where((n) => n.kind == NestedAttackKind.staticEncrypted),
        hasLength(2),
      );
    });

    test('ignores malformed lines', () {
      const line = 'Sec 3 key A cuid 5bcbb2e4 nt0 garbage';
      expect(NestedNonceParser.parse(line), isEmpty);
    });

    test('treats two identical nonces as static-encrypted (not a pair)', () {
      // Two full samples but nt0 == nt1: no extra constraint, so not
      // recoverable as a weak-nested pair. Guards a silent wrong-key result.
      const line =
          'Sec 5 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 '
          'nt1 a0bbe1ef ks1 c70d97e3 par1 1110 dist 0';

      final nonce = NestedNonceParser.parse(line).single;
      expect(nonce.samples, hasLength(2));
      expect(nonce.hasPair, isFalse);
      expect(nonce.kind, NestedAttackKind.staticEncrypted);
    });

    test('drops a line whose second sample is present but malformed', () {
      // A valid first sample with a corrupt nt1 must not be silently downgraded
      // to a single-sample nonce — the whole line is dropped.
      const line =
          'Sec 6 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 '
          'nt1 zzzzzzzz ks1 8a2107ad par1 1010 dist 0';
      expect(NestedNonceParser.parse(line), isEmpty);
    });

    test('drops a sample with an out-of-range (non 32-bit) value', () {
      const line =
          'Sec 6 key A cuid 5bcbb2e4 nt0 1a0bbe1ef ks0 c70d97e3 par0 1110';
      expect(NestedNonceParser.parse(line), isEmpty);
    });

    test('rejects structurally invalid lines but keeps valid neighbours', () {
      const file = '''
Sec x key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110
Sec 0 key Z cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110
Sec 0 key A nt0 a0bbe1ef ks0 c70d97e3 par0 1110
Sec 1 key B cuid 5bcbb2e4 nt0 d7707ed1 ks0 65bc542b par0 0110 dist 0
''';
      final nonces = NestedNonceParser.parse(file);
      expect(nonces, hasLength(1));
      expect(nonces.single.sector, 1);
      expect(nonces.single.keyType, NestedKeyType.b);
    });

    test('drops a line whose sector is outside MIFARE Classic 4K', () {
      // No card has a sector past 39, so such a line is corrupt on its face.
      // It is also the input that breaks the candidate dictionary's fixed
      // width: 40-127 render a well-formed entry under a key index the device
      // never reaches, 128 and up render a 15-char line the device truncates
      // onto an unrelated index, and a negative sector renders a non-hex index
      // byte the on-device parser does not validate.
      const file = '''
Sec 40 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
Sec 128 key B cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
Sec -1 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
Sec 39 key B cuid 5bcbb2e4 nt0 d7707ed1 ks0 65bc542b par0 0110 dist 0
''';
      final nonces = NestedNonceParser.parse(file);
      expect(nonces, hasLength(1));
      expect(nonces.single.sector, 39);
    });

    test('drops a line whose cuid is not a 32-bit word', () {
      // The cuid names the on-device dictionary file, and int.tryParse would
      // happily take a 16-hex-digit value (wrapping it negative) - which would
      // be written to a path the firmware never opens.
      const file = '''
Sec 0 key A cuid 15bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 0
Sec 1 key B cuid 5bcbb2e4 nt0 d7707ed1 ks0 65bc542b par0 0110 dist 0
''';
      final nonces = NestedNonceParser.parse(file);
      expect(nonces, hasLength(1));
      expect(nonces.single.sector, 1);
    });

    test('parses dist as null when absent and as its value when present', () {
      const withoutDist =
          'Sec 0 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110';
      const withDist =
          'Sec 0 key A cuid 5bcbb2e4 nt0 a0bbe1ef ks0 c70d97e3 par0 1110 dist 5';
      expect(NestedNonceParser.parse(withoutDist).single.dist, isNull);
      expect(NestedNonceParser.parse(withDist).single.dist, 5);
    });
  });
}
