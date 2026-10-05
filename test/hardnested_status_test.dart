// The bridge's status codes, mapped.
//
// Its own test because the mapping is the only part of the hardnested path that
// can be reached without a loaded engine and an isolate - and because it is
// where a code the C side added and the Dart side did not notice goes wrong.
// That has already happened once: `-4` was introduced for the re-entrancy
// refusal and fell into the "unknown status" arm, which logs that this build
// and the native side disagree about a code this build defines.
import 'package:flutter_test/flutter_test.dart';

import 'package:qunleashed/pages/tools/mifare/hardnested_recoverer.dart';

void main() {
  test('a key comes back with the key', () {
    final result = hardnestedResultFor(0, 0xA0A1A2A3A4A5);
    expect(result.outcome, HardnestedOutcome.found);
    expect(result.key, BigInt.parse('A0A1A2A3A4A5', radix: 16));
  });

  // Each of these is a different thing to tell someone: their card, their
  // device, their own Stop, or a bug in this app.
  test('every status the bridge documents has its own meaning', () {
    expect(hardnestedResultFor(-10, 0).outcome, HardnestedOutcome.noKey);
    expect(hardnestedResultFor(-3, 0).outcome, HardnestedOutcome.stopped);
    expect(hardnestedResultFor(-1, 0).outcome, HardnestedOutcome.outOfMemory);
    expect(hardnestedResultFor(-4, 0).outcome, HardnestedOutcome.engineBusy);
    expect(hardnestedResultFor(-2, 0).outcome, HardnestedOutcome.engineFault);
  });

  test('a status this build does not know is the engine, not the card', () {
    expect(hardnestedResultFor(-99, 0).outcome, HardnestedOutcome.engineFault);
  });

  // Only a success carries one. A key reported alongside a failure would be
  // written to the user's dictionary on the strength of an outcome that says
  // the attack did not succeed.
  test('no outcome but found carries a key', () {
    for (final status in [-1, -2, -3, -4, -10, -99]) {
      expect(
        hardnestedResultFor(status, 0xA0A1A2A3A4A5).key,
        isNull,
        reason: 'status $status reported a key',
      );
    }
  });
}
