import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'mifare_native.dart';

/// Recovers a hardened-PRNG (hardnested) MIFARE Classic sector key from the
/// encrypted nonces collected into `.nested.log`. The whole ciphertext-only
/// attack runs on the app host via the native `qunleashed_hardnested_recover`
/// (bitflip tables are embedded in the native lib - nothing to bundle/extract).
abstract class HardnestedRecoverer {
  /// Recovers the sector key from [ntEnc]/[parEnc] (parallel arrays, one entry
  /// per collected nonce) for card [cuid], or null if it could not be recovered.
  Future<BigInt?> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
  });
}

typedef _RecoverNative =
    Int32 Function(
      Uint32 cuid,
      Pointer<Uint32> ntEnc,
      Pointer<Uint8> parEnc,
      Uint32 count,
      Pointer<Uint64> found,
    );

typedef _RecoverDart =
    int Function(
      int cuid,
      Pointer<Uint32> ntEnc,
      Pointer<Uint8> parEnc,
      int count,
      Pointer<Uint64> found,
    );

class NativeHardnestedRecoverer implements HardnestedRecoverer {
  NativeHardnestedRecoverer();

  @override
  Future<BigInt?> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
  }) {
    // Needs at least two nonces (the engine consumes them in pairs) and the
    // arrays must line up.
    if (ntEnc.length < 2 || ntEnc.length != parEnc.length) {
      return Future.value(null);
    }
    final payload = _HardnestedPayload(
      cuid: cuid,
      ntEnc: Uint32List.fromList(ntEnc),
      parEnc: Uint8List.fromList(parEnc),
    );
    return Isolate.run(() => _recoverInIsolate(payload));
  }

  static BigInt? _recoverInIsolate(_HardnestedPayload p) {
    final recover = openHardnestedNativeLibrary()
        .lookupFunction<_RecoverNative, _RecoverDart>(
          'qunleashed_hardnested_recover',
        );
    final count = p.ntEnc.length;
    final ntPtr = calloc<Uint32>(count);
    final parPtr = calloc<Uint8>(count);
    final found = calloc<Uint64>();
    try {
      ntPtr.asTypedList(count).setAll(0, p.ntEnc);
      parPtr.asTypedList(count).setAll(0, p.parEnc);
      final result = recover(p.cuid, ntPtr, parPtr, count, found);
      if (result != 0) return null;
      return BigInt.from(found.value);
    } finally {
      calloc.free(ntPtr);
      calloc.free(parPtr);
      calloc.free(found);
    }
  }
}

class _HardnestedPayload {
  const _HardnestedPayload({
    required this.cuid,
    required this.ntEnc,
    required this.parEnc,
  });

  final int cuid;
  final Uint32List ntEnc;
  final Uint8List parEnc;
}
