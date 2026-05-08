import 'dart:ffi';
import 'dart:io';

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

  _RecoverDart? _recover;

  @override
  Future<BigInt?> bruteforceKey(MfKey32Nonce nonce) {
    return Future<BigInt?>.sync(() {
      final recover = _recover ??= _loadRecover();
      final found = calloc<Int32>();
      try {
        final key = recover(
          nonce.uid,
          nonce.nt0,
          nonce.nr0,
          nonce.ar0,
          nonce.nt1,
          nonce.nr1,
          nonce.ar1,
          found,
        );
        if (found.value == 0) return null;
        return BigInt.from(key);
      } finally {
        calloc.free(found);
      }
    });
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
