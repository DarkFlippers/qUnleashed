import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';

void main() {
  group('NativeHardnestedRecoverer input validation', () {
    test('empty nonces return null without extracting tables', () async {
      var providerCalled = false;
      final recoverer = NativeHardnestedRecoverer(
        tablesRootProvider: () async {
          providerCalled = true;
          return '/unused';
        },
      );

      expect(
        await recoverer.recoverKey(cuid: 0x11223344, ntEnc: [], parEnc: []),
        isNull,
      );
      // Short-circuits before touching platform channels / the native lib.
      expect(providerCalled, isFalse);
    });

    test(
      'mismatched nt/par lengths return null without extracting tables',
      () async {
        var providerCalled = false;
        final recoverer = NativeHardnestedRecoverer(
          tablesRootProvider: () async {
            providerCalled = true;
            return '/unused';
          },
        );

        expect(
          await recoverer.recoverKey(
            cuid: 0x11223344,
            ntEnc: [1, 2, 3],
            parEnc: [0, 1],
          ),
          isNull,
        );
        expect(providerCalled, isFalse);
      },
    );
  });
}
