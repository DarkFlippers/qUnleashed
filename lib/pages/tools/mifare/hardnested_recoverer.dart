import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'hardnested_tables.dart';
import 'mifare_native.dart';

/// Recovers a hardened-PRNG (hardnested) MIFARE Classic sector key from the
/// encrypted nonces collected into `.nested.log`. The whole ciphertext-only
/// attack runs on the app host via the native `qunleashed_hardnested_recover`.
abstract class HardnestedRecoverer {
  /// Recovers the sector key from [ntEnc]/[parEnc] (parallel arrays, one entry
  /// per collected nonce) for card [cuid], or null if it could not be recovered
  /// (too few nonces, or no key found).
  Future<BigInt?> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
  });
}

typedef _SetTablesPathNative = Void Function(Pointer<Utf8> path);
typedef _SetTablesPathDart = void Function(Pointer<Utf8> path);

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
  /// [tablesRootProvider] resolves (extracting on first use) the directory that
  /// contains `hardnested_tables/`; defaults to the bundled-asset extractor.
  /// Injectable so the extraction can be stubbed in tests.
  NativeHardnestedRecoverer({Future<String> Function()? tablesRootProvider})
    : _tablesRootProvider = tablesRootProvider ?? ensureHardnestedTables;

  final Future<String> Function() _tablesRootProvider;

  @override
  Future<BigInt?> recoverKey({
    required int cuid,
    required List<int> ntEnc,
    required List<int> parEnc,
  }) async {
    if (ntEnc.isEmpty || ntEnc.length != parEnc.length) return null;

    // Tables extraction needs platform channels, so resolve the directory on the
    // main isolate and pass only the path into the recovery isolate.
    final tablesRoot = await _tablesRootProvider();
    final payload = _HardnestedPayload(
      cuid: cuid,
      ntEnc: Uint32List.fromList(ntEnc),
      parEnc: Uint8List.fromList(parEnc),
      tablesRoot: tablesRoot,
    );
    return Isolate.run(() => _recoverInIsolate(payload));
  }

  static BigInt? _recoverInIsolate(_HardnestedPayload p) {
    final library = openMifareNativeLibrary();
    final setTablesPath = library
        .lookupFunction<_SetTablesPathNative, _SetTablesPathDart>(
          'qunleashed_hardnested_set_tables_path',
        );
    final recover = library.lookupFunction<_RecoverNative, _RecoverDart>(
      'qunleashed_hardnested_recover',
    );

    final count = p.ntEnc.length;
    final pathPtr = p.tablesRoot.toNativeUtf8();
    final ntPtr = calloc<Uint32>(count);
    final parPtr = calloc<Uint8>(count);
    final found = calloc<Uint64>();
    try {
      setTablesPath(pathPtr);
      ntPtr.asTypedList(count).setAll(0, p.ntEnc);
      parPtr.asTypedList(count).setAll(0, p.parEnc);
      final result = recover(p.cuid, ntPtr, parPtr, count, found);
      if (result != 0) return null;
      return BigInt.from(found.value);
    } finally {
      calloc.free(pathPtr);
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
    required this.tablesRoot,
  });

  final int cuid;
  final Uint32List ntEnc;
  final Uint8List parEnc;
  final String tablesRoot;
}
