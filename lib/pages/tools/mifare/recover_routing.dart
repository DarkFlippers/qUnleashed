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

/// Collapses tag lines that target the same card/sector/key, keeping the first.
///
/// Each is independently recoverable, so one per (cuid, sector, key) suffices -
/// and the same sector key read five times is still one sector key, which is
/// what anything counting or reporting before the attack needs. The key type is
/// part of the identity: without it, A and B of one sector collapse into one
/// and half of every sector is dropped before anything else sees it.
List<NestedNonce> dedupeNestedNonces(Iterable<NestedNonce> nonces) =>
    _dedupeBy(nonces, (n) => '${n.cuid}-${n.sector}-${n.keyType}');

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

/// A static-encrypted batch split into the nonces still worth attacking and the
/// ones a dictionary already answers.
typedef StaticSplit = ({
  List<NestedNonce> attack,
  Map<NestedNonce, BigInt> known,
});

/// Decides which static-encrypted nonces can be skipped because [lookup]
/// already has their key.
///
/// Sector at a time, never key at a time. `buildStaticDicts` solves a sector's
/// two keys together - cross-filtering A against B on their shared seednt16 -
/// and falls back to the parity-only set for a lone key. Dropping the known
/// half of a sector would leave the other half with no partner and a candidate
/// list several times *larger*: the opposite of the point, and invisible except
/// as a card that takes much longer on the device.
///
/// Here rather than in the controller because it is the kind of taxonomy this
/// file exists for - wrong in a way nothing downstream would reveal.
StaticSplit splitKnownStatic(
  Iterable<NestedNonce> singles,
  BigInt? Function(NestedNonce nonce) lookup,
) {
  final bySector = <String, List<NestedNonce>>{};
  for (final n in singles) {
    bySector.putIfAbsent('${n.cuid}-${n.sector}', () => []).add(n);
  }

  final attack = <NestedNonce>[];
  final known = <NestedNonce, BigInt>{};
  for (final group in bySector.values) {
    final hits = <NestedNonce, BigInt>{};
    for (final n in group) {
      final key = lookup(n);
      if (key != null) hits[n] = key;
    }
    if (hits.length == group.length) {
      known.addAll(hits);
    } else {
      attack.addAll(group);
    }
  }
  return (attack: attack, known: known);
}
