import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'cuid_dict_format.dart';
import 'mifare_native.dart';
import 'nested_models.dart';

/// Per-CUID candidate dictionary produced for the static-encrypted /
/// single-nonce path. A single nonce under-constrains the key (tens of
/// thousands of candidates), so these must be verified against the tag on the
/// device.
///
/// [body] is assembled inside the worker isolate so that formatting millions of
/// entries never runs on the UI isolate, and it carries the gaps that would
/// leave part of the card unattacked — see [CuidDictBody]. It is null when this
/// one card failed, in which case [error] says why; the other cards in the same
/// run still get their dictionaries.
class StaticCandidateDict {
  const StaticCandidateDict({required this.cuid, this.body, this.error})
    : assert(
        (body == null) != (error == null),
        'a card has either a dictionary or a reason it has none',
      );

  final int cuid;
  final CuidDictBody? body;
  final Object? error;
}

/// One card's nonce for a single (sector, key type), flattened to the scalars
/// the attack needs.
class StaticNonce {
  const StaticNonce({
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

/// A batch of candidates for one sector key. [atCapacity] means the generator
/// hit its output limit, so the real key may not be among [keys].
typedef CandidateBatch = ({Uint64List keys, bool atCapacity});

/// Both of a sector's candidate batches, labelled by key type so the two can
/// never be filed under each other's key index.
typedef CandidatePair = ({Uint64List keyA, Uint64List keyB, bool atCapacity});

abstract class StaticEncryptedRecoverer {
  /// Builds per-CUID candidate dictionaries from single-sample nonces. Sectors
  /// that expose both key A and key B are seednt-cross-filtered (FM11RF08S);
  /// lone keys fall back to the parity-filtered candidate set.
  Future<List<StaticCandidateDict>> buildCandidateDicts(
    List<NestedNonce> nonces,
  );
}

/// Groups [singles] by card and sector key and assembles one dictionary per
/// card, asking [solvePair] for a sector that exposes both keys and [solveOne]
/// for a lone key.
///
/// Candidate generation is injected, so the part that decides which key index
/// each candidate is filed under can be exercised without the native engine.
/// Either callback may return a view over a buffer it reuses on the next call:
/// each batch is consumed before the next is requested.
///
/// A card whose generation throws yields a [StaticCandidateDict] carrying the
/// error instead of a body, so one bad card costs one card.
List<StaticCandidateDict> buildStaticDicts(
  List<StaticNonce> singles, {
  required CandidatePair Function(int cuid, StaticNonce a, StaticNonce b)
  solvePair,
  required CandidateBatch Function(int cuid, StaticNonce one) solveOne,
}) {
  // cuid -> sector -> {isKeyA -> nonce}. Sectors are held in ascending order so
  // the file reads the way the firmware walks its key indices
  // (`current_key_idx++`, sector = index / 2). It rewinds and filters on the
  // index at every step, so that buys a deterministic file, not correctness.
  final grouped = <int, SplayTreeMap<int, Map<bool, StaticNonce>>>{};
  for (final s in singles) {
    grouped
            .putIfAbsent(s.cuid, SplayTreeMap.new)
            .putIfAbsent(s.sector, () => {})[s.isKeyA] =
        s;
  }

  final results = <StaticCandidateDict>[];
  grouped.forEach((cuid, sectors) {
    final builder = CuidDictBuilder();
    void emit(StaticNonce nonce, Uint64List keys, {required bool capped}) =>
        builder.add(
          sector: nonce.sector,
          isKeyA: nonce.isKeyA,
          keys: keys,
          atCapacity: capped,
        );

    try {
      for (final pair in sectors.values) {
        final a = pair[true];
        final b = pair[false];
        if (a != null && b != null) {
          final solved = solvePair(cuid, a, b);
          // A truncated enumeration on either key poisons the other's
          // cross-filter, so the flag applies to both.
          emit(a, solved.keyA, capped: solved.atCapacity);
          emit(b, solved.keyB, capped: solved.atCapacity);
        } else {
          final one = a ?? b!;
          final solved = solveOne(cuid, one);
          emit(one, solved.keys, capped: solved.atCapacity);
        }
      }
      results.add(StaticCandidateDict(cuid: cuid, body: builder.build()));
    } catch (e) {
      results.add(StaticCandidateDict(cuid: cuid, error: e));
    }
  });
  return results;
}

// Raw candidate buffers are sized well above the ~135k a single nonce was
// observed to yield (135075, for a 32-bit keystream via lfsr_recovery32). The
// cap is a defensive bound on an empirical maximum, not an expected outcome —
// reaching it is what `atCapacity` reports.
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
          (n) => StaticNonce(
            cuid: n.cuid,
            sector: n.sector,
            isKeyA: n.keyType == NestedKeyType.a,
            nt: n.samples[0].nt,
            ks: n.samples[0].ks,
            // The parser drops a lone sample without parity, so this holds for
            // every nonce that reaches here.
            par: n.par!,
          ),
        )
        .toList(growable: false);
    if (singles.isEmpty) return Future.value(const []);
    return Isolate.run(() => _buildInIsolate(singles));
  }

  static List<StaticCandidateDict> _buildInIsolate(List<StaticNonce> singles) {
    final _StaticDart staticFn;
    final _ReduceDart reduceFn;
    try {
      final library = openMifareNativeLibrary();
      staticFn = library.lookupFunction<_StaticNative, _StaticDart>(
        'qunleashed_static_candidates',
      );
      reduceFn = library.lookupFunction<_ReduceNative, _ReduceDart>(
        'qunleashed_rf08s_reduce_pair',
      );
    } catch (e) {
      // A missing library or symbol is a packaging fault, not a data one, and
      // must not reach the user as "this card could not be cracked".
      throw NativeEngineUnavailable(e);
    }

    // Allocated inside the try so a failure part-way through still frees what
    // was taken: native memory is process-scoped and outlives the isolate.
    Pointer<Uint64>? outA;
    Pointer<Uint64>? outB;
    Pointer<Uint32>? countA;
    Pointer<Uint32>? countB;
    Pointer<Uint32>? truncated;
    try {
      final bufA = outA = calloc<Uint64>(_capacity);
      final bufB = outB = calloc<Uint64>(_capacity);
      final cntA = countA = calloc<Uint32>();
      final cntB = countB = calloc<Uint32>();
      final trunc = truncated = calloc<Uint32>();
      return buildStaticDicts(
        singles,
        solvePair: (cuid, a, b) {
          reduceFn(
            cuid,
            a.nt,
            a.ks,
            a.par,
            b.nt,
            b.ks,
            b.par,
            bufA,
            _capacity,
            cntA,
            bufB,
            _capacity,
            cntB,
            trunc,
          );
          // The counts come back post-cross-filter, so they cannot reveal a
          // truncated enumeration; the native side reports that separately.
          return (
            keyA: bufA.asTypedList(cntA.value),
            keyB: bufB.asTypedList(cntB.value),
            atCapacity: trunc.value != 0,
          );
        },
        solveOne: (cuid, one) {
          final n = staticFn(cuid, one.nt, one.ks, one.par, bufA, _capacity);
          return (keys: bufA.asTypedList(n), atCapacity: n >= _capacity);
        },
      );
    } finally {
      if (outA != null) calloc.free(outA);
      if (outB != null) calloc.free(outB);
      if (countA != null) calloc.free(countA);
      if (countB != null) calloc.free(countB);
      if (truncated != null) calloc.free(truncated);
    }
  }
}
