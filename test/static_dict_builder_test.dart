import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/static_encrypted_recoverer.dart';

StaticNonce _nonce({
  int cuid = 0x5bcbb2e4,
  required int sector,
  required bool isKeyA,
}) => StaticNonce(
  cuid: cuid,
  sector: sector,
  isKeyA: isKeyA,
  nt: 0xa0bbe1ef,
  ks: 0xc70d97e3,
  par: 0xE,
);

Uint64List _keys(List<int> values) => Uint64List.fromList(values);

List<String> _lines(Uint8List bytes) =>
    String.fromCharCodes(bytes).trimRight().split('\n');

/// A pair solver that never runs — for cases with no two-key sector.
CandidatePair _noPair(int cuid, StaticNonce a, StaticNonce b) =>
    throw StateError('solvePair should not have been called');

/// A lone solver that never runs — for cases where every sector has both keys.
CandidateBatch _noSingle(int cuid, StaticNonce one) =>
    throw StateError('solveOne should not have been called');

void main() {
  group('buildStaticDicts', () {
    test('files key A and key B candidates under their own indices', () {
      // The regression this whole flow exists to prevent: key A's candidates
      // reaching the device under key B's index (or merged with them) means
      // the device tries neither against the right sector key.
      final dicts = buildStaticDicts(
        [_nonce(sector: 3, isKeyA: true), _nonce(sector: 3, isKeyA: false)],
        solvePair: (cuid, a, b) => (
          keyA: _keys([0xAAAAAAAAAAAA]),
          keyB: _keys([0xBBBBBBBBBBBB]),
          atCapacity: false,
        ),
        solveOne: _noSingle,
      );

      final body = dicts.single.body!;
      expect(_lines(body.bytes), ['06AAAAAAAAAAAA', '07BBBBBBBBBBBB']);
      expect(body.isComplete, isTrue);
    });

    test('a lone key keeps its own index rather than defaulting to key A', () {
      final dicts = buildStaticDicts(
        [_nonce(sector: 7, isKeyA: false)],
        solvePair: _noPair,
        solveOne: (cuid, one) =>
            (keys: _keys([0xCCCCCCCCCCCC]), atCapacity: false),
      );

      expect(_lines(dicts.single.body!.bytes), ['0FCCCCCCCCCCCC']);
    });

    test(
      'sectors are written in ascending order whatever order they arrive',
      () {
        final dicts = buildStaticDicts(
          [
            _nonce(sector: 9, isKeyA: true),
            _nonce(sector: 1, isKeyA: true),
            _nonce(sector: 4, isKeyA: false),
          ],
          solvePair: _noPair,
          solveOne: (cuid, one) =>
              (keys: _keys([0x000000000001]), atCapacity: false),
        );

        expect(_lines(dicts.single.body!.bytes), [
          '02000000000001', // sector 1, key A -> index 2
          '09000000000001', // sector 4, key B -> index 9
          '12000000000001', // sector 9, key A -> index 18 (0x12)
        ]);
      },
    );

    test('each card gets its own dictionary', () {
      final dicts = buildStaticDicts(
        [
          _nonce(cuid: 0x11111111, sector: 0, isKeyA: true),
          _nonce(cuid: 0x22222222, sector: 0, isKeyA: true),
        ],
        solvePair: _noPair,
        solveOne: (cuid, one) =>
            (keys: _keys([cuid & 0xFFFFFFFFFFFF]), atCapacity: false),
      );

      expect(dicts.map((d) => d.cuid), [0x11111111, 0x22222222]);
      expect(_lines(dicts[0].body!.bytes), ['00000011111111']);
      expect(_lines(dicts[1].body!.bytes), ['00000022222222']);
    });

    test('a truncated pair marks both keys, not just the capped one', () {
      // A partial candidate list yields a partial seed bitmap, so the
      // cross-filter can drop the real key from the other list too.
      final dicts = buildStaticDicts(
        [_nonce(sector: 2, isKeyA: true), _nonce(sector: 2, isKeyA: false)],
        solvePair: (cuid, a, b) => (
          keyA: _keys([0xAAAAAAAAAAAA]),
          keyB: _keys([0xBBBBBBBBBBBB]),
          atCapacity: true,
        ),
        solveOne: _noSingle,
      );

      expect(dicts.single.body!.cappedKeys, ['2A', '2B']);
    });

    test('one failing card costs one card, and names itself', () {
      // A throw used to unwind the whole batch, discarding every dictionary
      // already built and filing the note under whichever card came first.
      final dicts = buildStaticDicts(
        [
          _nonce(cuid: 0x11111111, sector: 0, isKeyA: true),
          _nonce(cuid: 0x22222222, sector: 0, isKeyA: true),
          _nonce(cuid: 0x33333333, sector: 0, isKeyA: true),
        ],
        solvePair: _noPair,
        solveOne: (cuid, one) {
          if (cuid == 0x22222222) throw ArgumentError('bad candidate');
          return (keys: _keys([0x000000000002]), atCapacity: false);
        },
      );

      expect(dicts.map((d) => d.cuid), [0x11111111, 0x22222222, 0x33333333]);
      expect(dicts[0].body, isNotNull);
      expect(dicts[1].body, isNull);
      expect(dicts[1].error, isArgumentError);
      expect(dicts[2].body, isNotNull);
    });

    test(
      'a card whose every sector key came back empty has no body to write',
      () {
        final dicts = buildStaticDicts(
          [_nonce(sector: 5, isKeyA: true)],
          solvePair: _noPair,
          solveOne: (cuid, one) => (keys: Uint64List(0), atCapacity: false),
        );

        final body = dicts.single.body!;
        expect(body.isEmpty, isTrue);
        expect(body.skippedKeys, ['5A']);
      },
    );

    test('no nonces yields no dictionaries', () {
      expect(
        buildStaticDicts([], solvePair: _noPair, solveOne: _noSingle),
        isEmpty,
      );
    });
  });
}
