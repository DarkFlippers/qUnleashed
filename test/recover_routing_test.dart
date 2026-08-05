import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/mfkey32_models.dart';
import 'package:qunleashed/pages/tools/mifare/nested_models.dart';
import 'package:qunleashed/pages/tools/mifare/recover_models.dart';
import 'package:qunleashed/pages/tools/mifare/recover_routing.dart';

/// Single-sample nested line (hardnested when [dist] is null, static-encrypted
/// when a [dist] is present — regardless of its value).
NestedNonce single({
  int cuid = 0x11111111,
  int sector = 0,
  NestedKeyType keyType = NestedKeyType.a,
  int? dist,
  int nt = 0x11223344,
}) => NestedNonce(
  sector: sector,
  keyType: keyType,
  cuid: cuid,
  dist: dist,
  samples: [NestedSample(nt: nt, ks: 0, par: 0)],
);

/// Two-sample nested line with distinct nonces (weak / static-nonce).
NestedNonce pair({
  int cuid = 0x22222222,
  int sector = 1,
  NestedKeyType keyType = NestedKeyType.a,
  int? dist,
}) => NestedNonce(
  sector: sector,
  keyType: keyType,
  cuid: cuid,
  dist: dist,
  samples: const [
    NestedSample(nt: 0xAAAAAAAA, ks: 0, par: 0),
    NestedSample(nt: 0xBBBBBBBB, ks: 0, par: 0),
  ],
);

MfKey32Nonce reader({
  int uid = 0x33333333,
  String sectorName = '0',
  String keyName = 'A',
}) => MfKey32Nonce(
  sectorName: sectorName,
  keyName: keyName,
  uid: uid,
  nt0: 0,
  nr0: 0,
  ar0: 0,
  nt1: 0,
  nr1: 0,
  ar1: 0,
);

void main() {
  group('splitSingles', () {
    test('a single carrying a dist routes to static-encrypted', () {
      final (statics, hard) = splitSingles([single(dist: 5)]);
      expect(statics, hasLength(1));
      expect(hard, isEmpty);
    });

    test('a single without a dist routes to hardnested', () {
      final (statics, hard) = splitSingles([single(dist: null)]);
      expect(statics, isEmpty);
      expect(hard, hasLength(1));
      expect(hard.single, hasLength(1));
    });

    // The taxonomy pivots on dist *presence*, not its value: dist == 0 is a
    // static-encrypted FM11RF08S line, not a hardnested one. (Regression guard:
    // this was previously mis-routed.)
    test('dist == 0 is static-encrypted, not hardnested', () {
      final (statics, hard) = splitSingles([single(dist: 0)]);
      expect(statics, hasLength(1));
      expect(hard, isEmpty);
    });

    test('hardnested singles group by (cuid, sector, key)', () {
      final (statics, hard) = splitSingles([
        single(cuid: 1, sector: 3, keyType: NestedKeyType.a),
        single(cuid: 1, sector: 3, keyType: NestedKeyType.a),
        single(cuid: 1, sector: 3, keyType: NestedKeyType.b),
        single(cuid: 2, sector: 3, keyType: NestedKeyType.a),
      ]);
      expect(statics, isEmpty);
      // (1,3,A) has two nonces; (1,3,B) and (2,3,A) one each.
      expect(hard.map((g) => g.length).toList()..sort(), [1, 1, 2]);
    });

    test('mixed singles split into their two buckets', () {
      final (statics, hard) = splitSingles([
        single(dist: 7),
        single(dist: null, sector: 4),
        single(dist: 0),
      ]);
      expect(statics, hasLength(2));
      expect(hard, hasLength(1));
    });

    test('empty input yields empty buckets', () {
      final (statics, hard) = splitSingles(const []);
      expect(statics, isEmpty);
      expect(hard, isEmpty);
    });
  });

  group('weakKind', () {
    test('dist == 0 is a static nonce', () {
      expect(weakKind(pair(dist: 0)), RecoverKind.staticNonce);
    });

    test('a nonzero dist is a weak PRNG', () {
      expect(weakKind(pair(dist: 42)), RecoverKind.weakNested);
    });

    test('a missing dist defaults to weak nested', () {
      expect(weakKind(pair(dist: null)), RecoverKind.weakNested);
    });
  });

  group('dedupeReaderNonces', () {
    test('collapses duplicate uid/sector/key, keeping the first', () {
      final first = reader(uid: 9, sectorName: '2', keyName: 'A');
      final result = dedupeReaderNonces([
        first,
        reader(uid: 9, sectorName: '2', keyName: 'A'),
      ]);
      expect(result, hasLength(1));
      expect(identical(result.single, first), isTrue);
    });

    test('keeps distinct sectors and keys', () {
      final result = dedupeReaderNonces([
        reader(uid: 9, sectorName: '2', keyName: 'A'),
        reader(uid: 9, sectorName: '2', keyName: 'B'),
        reader(uid: 9, sectorName: '3', keyName: 'A'),
      ]);
      expect(result, hasLength(3));
    });
  });

  group('dedupeWeakNonces', () {
    test('collapses duplicate cuid/sector/key', () {
      final result = dedupeWeakNonces([
        pair(cuid: 5, sector: 1, keyType: NestedKeyType.a),
        pair(cuid: 5, sector: 1, keyType: NestedKeyType.a),
      ]);
      expect(result, hasLength(1));
    });

    test('keeps distinct cards and key types', () {
      final result = dedupeWeakNonces([
        pair(cuid: 5, sector: 1, keyType: NestedKeyType.a),
        pair(cuid: 5, sector: 1, keyType: NestedKeyType.b),
        pair(cuid: 6, sector: 1, keyType: NestedKeyType.a),
      ]);
      expect(result, hasLength(3));
    });
  });
}
