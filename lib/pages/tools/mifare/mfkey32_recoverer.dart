import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'mfkey32_models.dart';

abstract class MfKey32Recoverer {
  Future<BigInt?> bruteforceKey(MfKey32Nonce nonce);
}

typedef _RecoverNative = Uint64 Function(
  Uint32 uid,
  Uint32 nt0,
  Uint32 nr0,
  Uint32 ar0,
  Uint32 nt1,
  Uint32 nr1,
  Uint32 ar1,
  Pointer<Int32> found,
);

typedef _RecoverDart = int Function(
  int uid,
  int nt0,
  int nr0,
  int ar0,
  int nt1,
  int nr1,
  int ar1,
  Pointer<Int32> found,
);

class NativeMfKey32Recoverer implements MfKey32Recoverer {
  NativeMfKey32Recoverer();

  @override
  Future<BigInt?> bruteforceKey(MfKey32Nonce nonce) {
    final payload = _RecoverPayload(
      nonce.uid,
      nonce.nt0,
      nonce.nr0,
      nonce.ar0,
      nonce.nt1,
      nonce.nr1,
      nonce.ar1,
    );
    return Isolate.run(() => _recoverInIsolate(payload));
  }

  static BigInt? _recoverInIsolate(_RecoverPayload p) {
    final recover = _loadRecover();
    final found = calloc<Int32>();
    try {
      final key = recover(p.uid, p.nt0, p.nr0, p.ar0, p.nt1, p.nr1, p.ar1, found);
      if (found.value == 0) return null;
      return BigInt.from(key);
    } finally {
      calloc.free(found);
    }
  }

  static _RecoverDart _loadRecover() {
    final library = _openLibrary();
    return library.lookupFunction<_RecoverNative, _RecoverDart>(
      'qunleashed_mfkey32_recover_key',
    );
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libqunleashed_mfkey32.so');
    }
    if (Platform.isWindows) {
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final bundledPath =
          '$executableDir${Platform.pathSeparator}qunleashed_mfkey32.dll';
      if (File(bundledPath).existsSync()) {
        return DynamicLibrary.open(bundledPath);
      }
      return DynamicLibrary.open('qunleashed_mfkey32.dll');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform for MfKey32 native library');
  }
}

class _RecoverPayload {
  const _RecoverPayload(
    this.uid,
    this.nt0,
    this.nr0,
    this.ar0,
    this.nt1,
    this.nr1,
    this.ar1,
  );

  final int uid;
  final int nt0;
  final int nr0;
  final int ar0;
  final int nt1;
  final int nr1;
  final int ar1;
}
