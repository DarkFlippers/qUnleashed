import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';

void main() {
  group('NativeHardnestedRecoverer input validation', () {
    // These inputs short-circuit to null before any isolate / native call.
    test('empty nonces return null', () async {
      final recoverer = NativeHardnestedRecoverer();
      expect(
        await recoverer.recoverKey(cuid: 0x11223344, ntEnc: [], parEnc: []),
        isNull,
      );
    });

    test('mismatched nt/par lengths return null', () async {
      final recoverer = NativeHardnestedRecoverer();
      expect(
        await recoverer.recoverKey(
          cuid: 0x11223344,
          ntEnc: [1, 2, 3],
          parEnc: [0, 1],
        ),
        isNull,
      );
    });

    test('a single nonce returns null (the engine needs a pair)', () async {
      final recoverer = NativeHardnestedRecoverer();
      expect(
        await recoverer.recoverKey(cuid: 0x11223344, ntEnc: [1], parEnc: [0]),
        isNull,
      );
    });
  });
}
