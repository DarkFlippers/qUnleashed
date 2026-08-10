/// Pure routing helpers for [RecoverController], extracted so the dist-based
/// taxonomy — the part that distinguishes static-encrypted, hardnested, weak
/// and static-nonce lines, and which has been subtly wrong before — is unit
/// testable in isolation from the device/FFI plumbing.
library;

import 'mfkey32_models.dart';
import 'nested_models.dart';
import 'recover_models.dart';

/// Collapses [items] to the first occurrence of each distinct [keyOf] value.
List<T> _dedupeBy<T>(Iterable<T> items, String Function(T) keyOf) {
  final byKey = <String, T>{};
  for (final item in items) {
    byKey.putIfAbsent(keyOf(item), () => item);
  }
  return byKey.values.toList(growable: false);
}

/// Collapses reader (`.mfkey32.log`) nonces that target the same uid/sector/key,
/// keeping the first. A card read repeatedly yields many identical nonces;
/// recovering each once is enough.
List<MfKey32Nonce> dedupeReaderNonces(List<MfKey32Nonce> nonces) =>
    _dedupeBy(nonces, (n) => '${n.uid}-${n.sectorName}-${n.keyName}');

/// Collapses two-sample (weak / static-nonce) tag lines that target the same
/// card/sector/key, keeping the first. Each is independently recoverable, so one
/// per (cuid, sector, key) suffices.
List<NestedNonce> dedupeWeakNonces(Iterable<NestedNonce> pairs) =>
    _dedupeBy(pairs, (n) => '${n.cuid}-${n.sector}-${n.keyType}');

/// Splits single-sample nested nonces the way the firmware distinguishes them:
/// a line that carries a `dist` field is static-encrypted (FM11RF08S); one
/// without is hardnested. Hardnested nonces are grouped by (cuid, sector, key)
/// into the nonce set each attack runs over.
(List<NestedNonce>, List<List<NestedNonce>>) splitSingles(
  Iterable<NestedNonce> singles,
) {
  final staticSingles = <NestedNonce>[];
  final hardGroups = <String, List<NestedNonce>>{};
  for (final n in singles) {
    if (n.dist != null) {
      staticSingles.add(n);
    } else {
      hardGroups
          .putIfAbsent('${n.cuid}-${n.sector}-${n.keyType}', () => [])
          .add(n);
    }
  }
  return (staticSingles, hardGroups.values.toList(growable: false));
}

/// A two-sample nested line is a static-nonce tag when its PRNG distance is 0
/// (the nonce never advances) and a genuine weak-PRNG collection otherwise.
/// The crapto1 recovery is identical either way; only the label differs.
RecoverKind weakKind(NestedNonce n) =>
    n.dist == 0 ? RecoverKind.staticNonce : RecoverKind.weakNested;
