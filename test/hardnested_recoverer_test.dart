import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';

void main() {
  group('NativeHardnestedRecoverer input validation', () {
    // These inputs short-circuit to null before any isolate / native call.
    // Too few nonces is a statement about the collection, not a failure of the
    // attack, and it is answered without the engine being loaded at all.
    test('empty nonces return no key', () async {
      final recoverer = NativeHardnestedRecoverer();
      final result = await recoverer.recoverKey(
        cuid: 0x11223344,
        ntEnc: [],
        parEnc: [],
      );
      expect(result.key, isNull);
      expect(result.outcome, HardnestedOutcome.noKey);
    });

    test(
      'mismatched nt/par lengths assert (a caller bug, not a data case)',
      () {
        final recoverer = NativeHardnestedRecoverer();
        expect(
          () => recoverer.recoverKey(
            cuid: 0x11223344,
            ntEnc: [1, 2, 3],
            parEnc: [0, 1],
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('a single nonce returns no key (the engine needs a pair)', () async {
      final recoverer = NativeHardnestedRecoverer();
      final result = await recoverer.recoverKey(
        cuid: 0x11223344,
        ntEnc: [1],
        parEnc: [0],
      );
      expect(result.key, isNull);
      expect(result.outcome, HardnestedOutcome.noKey);
    });
  });

  // The engine's bitflip tables are a fixed cost on every attack, measured in
  // the build this runs against: 351 of them at 4 * ((1 << 19) + 1) bytes, so
  // 702 MiB before a single nonce is looked at. Android and iOS overcommit, so
  // the engine's own exit()-on-failure never fires there - the kernel kills the
  // process when the pages are touched. This judgement is the only place the
  // attack can be refused instead.
  group('hardnestedMemoryVerdict', () {
    const tables = 736101756; // what qunleashed_hn_table_bytes() returns

    test('plenty of room goes ahead', () {
      expect(
        hardnestedMemoryVerdict(tableBytes: tables, availableBytes: 2000000000),
        isNull,
      );
    });

    test('less than the tables themselves is refused', () {
      final refusal = hardnestedMemoryVerdict(
        tableBytes: tables,
        availableBytes: 400000000,
      );
      expect(refusal?.outcome, HardnestedOutcome.outOfMemory);
      expect(refusal?.key, isNull);
    });

    // The margin, which is the whole judgement: the tables are a floor, and the
    // sum-property bitarrays and candidate statelists sit on top of them. Room
    // for the tables and nothing else is not room for the attack.
    test('room for the tables but not the margin is refused', () {
      expect(
        hardnestedMemoryVerdict(
          tableBytes: tables,
          availableBytes: tables + 1000000,
        )?.outcome,
        HardnestedOutcome.outOfMemory,
      );
      expect(
        hardnestedMemoryVerdict(
          tableBytes: tables,
          availableBytes: (tables * 5) ~/ 4 + 1,
        ),
        isNull,
      );
    });

    // Both directions of "could not ask". A platform with no figure to report
    // (macOS, anything unknown) returns 0, and so does a failed read of
    // /proc/meminfo - neither is a statement that there is no memory. Refusing
    // on one would block attacks that work today.
    test('an unknown figure goes ahead rather than refusing', () {
      expect(
        hardnestedMemoryVerdict(tableBytes: tables, availableBytes: 0),
        isNull,
        reason: 'the OS did not answer',
      );
      expect(
        hardnestedMemoryVerdict(tableBytes: 0, availableBytes: 1000),
        isNull,
        reason: 'the engine did not answer',
      );
      expect(
        hardnestedMemoryVerdict(tableBytes: tables, availableBytes: -1),
        isNull,
        reason: 'a uint64 past 2^63 arrives negative; still not an answer',
      );
    });
  });
}
