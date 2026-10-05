import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';

void main() {
  group('NativeHardnestedRecoverer input validation', () {
    // These inputs short-circuit to null before any isolate / native call.
    // Too few nonces is a statement about the collection, not a failure of the
    // attack, so it comes back as noKey without the engine being loaded at all.
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
}
