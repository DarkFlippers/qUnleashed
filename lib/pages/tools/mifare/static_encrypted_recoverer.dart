import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'cuid_dict_format.dart';
import 'mifare_native.dart';
import 'nested_models.dart';

/// Per-CUID candidate dictionary produced for the static-encrypted / single-nonce
/// path. A single nonce under-constrains the key (tens of thousands of
/// candidates), so these must be verified against the tag on the device.
///
/// [body] is assembled inside the worker isolate so that formatting millions of
/// entries never runs on the UI isolate, and it carries the gaps that would
/// leave part of the card unattacked — see [CuidDictBody].
class StaticCandidateDict {
  const StaticCandidateDict({required this.cuid, required this.body});

  final int cuid;
  final CuidDictBody body;
}

abstract class StaticEncryptedRecoverer {
  /// Builds per-CUID candidate dictionaries from single-sample nonces. Sectors
  /// that expose both key A and key B are seednt-cross-filtered (FM11RF08S);
  /// lone keys fall back to the parity-filtered candidate set.
  Future<List<StaticCandidateDict>> buildCandidateDicts(
    List<NestedNonce> nonces,
  );
}

// Raw candidate buffers are sized above the ~135k maximum a single nonce yields
// (observed: 135075 for a 32-bit keystream via lfsr_recovery32).
const _capacity = 1 << 18;

typedef _StaticNative =
    Uint32 Function(Uint32, Uint32, Uint32, Uint32, Pointer<Uint64>, Uint32);
typedef _StaticDart = int Function(int, int, int, int, Pointer<Uint64>, int);

typedef _ReduceNative =
    Void Function(
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Pointer<Uint64>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint64>,
      Uint32,
      Pointer<Uint32>,
    );
typedef _ReduceDart =
    void Function(
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      Pointer<Uint64>,
      int,
      Pointer<Uint32>,
      Pointer<Uint64>,
      int,
      Pointer<Uint32>,
    );

class NativeStaticEncryptedRecoverer implements StaticEncryptedRecoverer {
  @override
  Future<List<StaticCandidateDict>> buildCandidateDicts(
    List<NestedNonce> nonces,
  ) {
    final singles = nonces
        .where((n) => !n.hasPair)
        .map(
          (n) => _NoncePayload(
            cuid: n.cuid,
            sector: n.sector,
            isKeyA: n.keyType == NestedKeyType.a,
            nt: n.samples[0].nt,
            ks: n.samples[0].ks,
            par: n.samples[0].par,
          ),
        )
        .toList(growable: false);
    if (singles.isEmpty) return Future.value(const []);
    return Isolate.run(() => _buildInIsolate(singles));
  }

  static List<StaticCandidateDict> _buildInIsolate(
    List<_NoncePayload> singles,
  ) {
    final library = openMifareNativeLibrary();
    final staticFn = library.lookupFunction<_StaticNative, _StaticDart>(
      'qunleashed_static_candidates',
    );
    final reduceFn = library.lookupFunction<_ReduceNative, _ReduceDart>(
      'qunleashed_rf08s_reduce_pair',
    );

    final outA = calloc<Uint64>(_capacity);
    final outB = calloc<Uint64>(_capacity);
    final countA = calloc<Uint32>();
    final countB = calloc<Uint32>();
    try {
      // cuid -> sector -> {isKeyA -> payload}. Sectors are held in ascending
      // order so the file reads the way the firmware walks its key indices
      // (`current_key_idx++`, sector = index / 2). It rewinds and filters on
      // the index at every step, so that buys a deterministic file, not
      // correctness.
      final grouped = <int, SplayTreeMap<int, Map<bool, _NoncePayload>>>{};
      for (final s in singles) {
        grouped
                .putIfAbsent(s.cuid, SplayTreeMap.new)
                .putIfAbsent(s.sector, () => {})[s.isKeyA] =
            s;
      }

      final results = <StaticCandidateDict>[];
      grouped.forEach((cuid, sectors) {
        final builder = CuidDictBuilder();
        // The native call writes into a buffer it reuses on the next sector, so
        // `asTypedList` hands back a view that only stays valid until then --
        // and `add` is documented to consume it before returning. A count that
        // reached the cap means the enumeration was cut short.
        void emit(_NoncePayload nonce, Uint64List keys) => builder.add(
          sector: nonce.sector,
          isKeyA: nonce.isKeyA,
          keys: keys,
          atCapacity: keys.length == _capacity,
        );

        for (final pair in sectors.values) {
          final a = pair[true];
          final b = pair[false];
          if (a != null && b != null) {
            reduceFn(
              cuid,
              a.nt,
              a.ks,
              a.par,
              b.nt,
              b.ks,
              b.par,
              outA,
              _capacity,
              countA,
              outB,
              _capacity,
              countB,
            );
            emit(a, outA.asTypedList(countA.value));
            emit(b, outB.asTypedList(countB.value));
          } else {
            final one = a ?? b!;
            final n = staticFn(cuid, one.nt, one.ks, one.par, outA, _capacity);
            emit(one, outA.asTypedList(n));
          }
        }
        results.add(StaticCandidateDict(cuid: cuid, body: builder.build()));
      });
      return results;
    } finally {
      calloc.free(outA);
      calloc.free(outB);
      calloc.free(countA);
      calloc.free(countB);
    }
  }
}

class _NoncePayload {
  const _NoncePayload({
    required this.cuid,
    required this.sector,
    required this.isKeyA,
    required this.nt,
    required this.ks,
    required this.par,
  });

  final int cuid;
  final int sector;
  final bool isKeyA;
  final int nt;
  final int ks;
  final int par;
}
