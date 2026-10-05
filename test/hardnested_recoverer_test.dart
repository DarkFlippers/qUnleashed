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

  // The engine allocates a fixed set before it reads a single nonce, and holds
  // all of it at once: the bitflip tables (~702 MiB), init_nonce_memory's
  // per-first-byte state bitarrays (1 GiB - the largest term, and the one a
  // tables-only figure misses), and the sum-property arrays (148 MiB). On
  // 64-bit Android and iOS none of those allocations fails: address space is
  // handed out lazily and the kernel kills the process when the pages are
  // touched, so the engine's own exit()-on-failure never runs. This judgement
  // is the only place the attack can be refused instead.
  group('hardnestedMemoryVerdict', () {
    // A copy, not a reading: the suite never loads the engine, so nothing here
    // fails if tables.c is re-vendored. These tests pin the judgement, not the
    // measurement - which is exactly why the measurement is computed in
    // hardnested.c beside the allocations rather than written down twice.
    const peak = 1969227132; // what qunleashed_hn_peak_bytes() returned
    final required = hardnestedRequiredBytes(peak);

    test('plenty of room goes ahead', () {
      expect(
        hardnestedMemoryVerdict(peakBytes: peak, availableBytes: peak * 2),
        isNull,
      );
    });

    test('less than the engine peak itself is refused', () {
      final refusal = hardnestedMemoryVerdict(
        peakBytes: peak,
        availableBytes: peak ~/ 2,
      );
      expect(refusal?.outcome, HardnestedOutcome.outOfMemory);
      expect(refusal?.key, isNull);
    });

    // The margin, and the direction of the comparison. Room for the engine's
    // own peak and nothing else is not room for the attack - the candidate
    // statelists and the app's own working set are still to come - so the
    // boundary sits at the requirement, not at the peak.
    test('the boundary is the requirement, not the peak', () {
      expect(
        hardnestedMemoryVerdict(
          peakBytes: peak,
          availableBytes: required - 1,
        )?.outcome,
        HardnestedOutcome.outOfMemory,
        reason: 'a byte short of the requirement is still short',
      );
      expect(
        hardnestedMemoryVerdict(peakBytes: peak, availableBytes: required),
        isNull,
        reason: 'and exactly the requirement is enough',
      );
      expect(
        required,
        greaterThan(peak),
        reason: 'a margin that did not add anything would not be one',
      );
    });

    // Both directions of "could not ask". A platform with no figure to report
    // (macOS, Windows, anything unknown) returns 0, and so does a failed read
    // of /proc/meminfo - neither is a statement that there is no memory.
    // Refusing on one would block attacks that work today.
    test('an unknown figure goes ahead rather than refusing', () {
      expect(
        hardnestedMemoryVerdict(peakBytes: peak, availableBytes: 0),
        isNull,
        reason: 'the OS did not answer',
      );
      expect(
        hardnestedMemoryVerdict(peakBytes: 0, availableBytes: 1000),
        isNull,
        reason: 'the engine did not answer',
      );
      expect(
        hardnestedMemoryVerdict(peakBytes: peak, availableBytes: -1),
        isNull,
        reason: 'a uint64 past 2^63 arrives negative; still not an answer',
      );
    });

    // The refusal line is the only record of why an attack never started, so it
    // has to name the figure the judgement used. It did not: it quoted the bare
    // peak while comparing against peak-plus-margin, so a refused run was
    // reported as "needs 702 MiB, has 800 MiB" - a sentence that reads as a
    // contradiction and sends a bug report after the wrong number.
    test('the refusal names the requirement, not just the peak', () {
      // Picked to be past the peak and short of the requirement, which is the
      // band the old wording made nonsense of.
      final available = (peak + required) ~/ 2;
      expect(
        hardnestedMemoryVerdict(
          peakBytes: peak,
          availableBytes: available,
        )?.outcome,
        HardnestedOutcome.outOfMemory,
        reason: 'the fixture has to be a case that is actually refused',
      );

      final message = hardnestedMemoryRefusal(
        peakBytes: peak,
        availableBytes: available,
      );
      expect(message, contains('${required >> 20} MiB'));
      expect(message, contains('${peak >> 20} MiB'));
      expect(message, contains('${available >> 20} MiB'));
    });
  });
}
