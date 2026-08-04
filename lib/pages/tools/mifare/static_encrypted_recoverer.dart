import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'mifare_native.dart';
import 'nested_models.dart';

/// Per-CUID candidate dictionary produced for the static-encrypted / single-nonce
/// path. A single nonce under-constrains the key (tens of thousands of
/// candidates), so these must be verified against the tag on the device.
class StaticCandidateDict {
  const StaticCandidateDict({required this.cuid, required this.keys});

  final int cuid;

  /// Candidate keys as 12-hex-digit uppercase strings, deduplicated.
  final List<String> keys;
}

abstract class StaticEncryptedRecoverer {
  /// Builds per-CUID candidate dictionaries from single-sample nonces. Sectors
  /// that expose both key A and key B are seednt-cross-filtered (FM11RF08S);
  /// lone keys fall back to the parity-filtered candidate set.
  Future<List<StaticCandidateDict>> buildCandidateDicts(
    List<NestedNonce> nonces,
  );
}

// Raw candidate buffers are sized above the ~135k maximum a single nonce yields.
const _capacity = 1 << 18;

typedef _StaticNative = Uint32 Function(
    Uint32, Uint32, Uint32, Uint32, Pointer<Uint64>, Uint32);
typedef _StaticDart = int Function(
    int, int, int, int, Pointer<Uint64>, int);

typedef _ReduceNative = Void Function(
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
    Pointer<Uint32>);
typedef _ReduceDart = void Function(
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
    Pointer<Uint32>);

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

  static List<StaticCandidateDict> _buildInIsolate(List<_NoncePayload> singles) {
    final library = openMifareNativeLibrary();
    final staticFn = library
        .lookupFunction<_StaticNative, _StaticDart>('qunleashed_static_candidates');
    final reduceFn = library
        .lookupFunction<_ReduceNative, _ReduceDart>('qunleashed_rf08s_reduce_pair');

    final outA = calloc<Uint64>(_capacity);
    final outB = calloc<Uint64>(_capacity);
    final countA = calloc<Uint32>();
    final countB = calloc<Uint32>();
    try {
      // cuid -> sector -> {isKeyA -> payload}
      final grouped = <int, Map<int, Map<bool, _NoncePayload>>>{};
      for (final s in singles) {
        grouped
            .putIfAbsent(s.cuid, () => {})
            .putIfAbsent(s.sector, () => {})[s.isKeyA] = s;
      }

      final results = <StaticCandidateDict>[];
      grouped.forEach((cuid, sectors) {
        final candidates = <int>{};
        for (final keys in sectors.values) {
          final a = keys[true];
          final b = keys[false];
          if (a != null && b != null) {
            reduceFn(cuid, a.nt, a.ks, a.par, b.nt, b.ks, b.par, outA, _capacity,
                countA, outB, _capacity, countB);
            candidates.addAll(outA.asTypedList(countA.value));
            candidates.addAll(outB.asTypedList(countB.value));
          } else {
            final one = a ?? b!;
            final n = staticFn(cuid, one.nt, one.ks, one.par, outA, _capacity);
            candidates.addAll(outA.asTypedList(n));
          }
        }
        results.add(
          StaticCandidateDict(
            cuid: cuid,
            keys: candidates
                .map((k) => k.toRadixString(16).padLeft(12, '0').toUpperCase())
                .toList(growable: false),
          ),
        );
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
