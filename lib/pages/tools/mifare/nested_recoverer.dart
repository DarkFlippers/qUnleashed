import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'mifare_native.dart';
import 'nested_models.dart';

abstract class NestedRecoverer {
  /// Recovers the sector key for a nested [nonce], or null if none was found.
  ///
  /// Only the two-sample (weak nested) case is uniquely recoverable on its own;
  /// single-sample static-encrypted nonces return null here.
  Future<BigInt?> recoverKey(NestedNonce nonce);
}

typedef _RecoverNative =
    Uint64 Function(
      Uint32 uid,
      Uint32 nt0,
      Uint32 ks0,
      Uint32 nt1,
      Uint32 ks1,
      Int32 hasSecond,
      Pointer<Int32> found,
    );

typedef _RecoverDart =
    int Function(
      int uid,
      int nt0,
      int ks0,
      int nt1,
      int ks1,
      int hasSecond,
      Pointer<Int32> found,
    );

class NativeNestedRecoverer implements NestedRecoverer {
  NativeNestedRecoverer();

  @override
  Future<BigInt?> recoverKey(NestedNonce nonce) {
    if (!nonce.hasPair) return Future.value(null);
    final first = nonce.samples[0];
    final second = nonce.samples[1];
    final payload = _RecoverPayload(
      nonce.cuid,
      first.nt,
      first.ks,
      second.nt,
      second.ks,
    );
    return Isolate.run(() => _recoverInIsolate(payload));
  }

  static BigInt? _recoverInIsolate(_RecoverPayload p) {
    final recover = openMifareNativeLibrary()
        .lookupFunction<_RecoverNative, _RecoverDart>(
          'qunleashed_nested_recover_key',
        );
    final found = calloc<Int32>();
    try {
      final key = recover(p.uid, p.nt0, p.ks0, p.nt1, p.ks1, 1, found);
      if (found.value == 0) return null;
      return BigInt.from(key);
    } finally {
      calloc.free(found);
    }
  }
}

class _RecoverPayload {
  const _RecoverPayload(this.uid, this.nt0, this.ks0, this.nt1, this.ks1);

  final int uid;
  final int nt0;
  final int ks0;
  final int nt1;
  final int ks1;
}
