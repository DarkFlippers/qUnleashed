// Covers the rule that decides which static-encrypted nonces can be skipped.
//
// Sector at a time, never key at a time. `buildStaticDicts` solves a sector's
// two keys together, cross-filtering A against B on their shared seednt16, and
// falls back to the parity-only set for a lone key. Dropping the known half of
// a sector would leave the other half with no partner and a candidate list
// several times *larger* - the opposite of the point, and invisible on screen
// except as a card that takes much longer on the device.
//
// Here rather than through the controller because that is what makes the
// half-known case expressible at all: a filter driven through a run answers the
// same for every nonce, so the branch this exists for cannot be reached.
import 'package:flutter_test/flutter_test.dart';

import 'package:qunleashed/pages/tools/mifare/nested_models.dart';
import 'package:qunleashed/pages/tools/mifare/recover_routing.dart';

NestedNonce _single(int sector, NestedKeyType key, {int cuid = 0xAABBCCDD}) =>
    NestedNonce(
      cuid: cuid,
      sector: sector,
      keyType: key,
      samples: const [NestedSample(nt: 1, ks: 2, par: 0xF)],
      dist: 0,
    );

void main() {
  final known = BigInt.parse('A0A1A2A3A4A5', radix: 16);

  // The case the rule exists for. Attacking B alone would cost it the
  // cross-filter and make its dictionary larger than attacking both.
  test('a sector with one key known is attacked whole', () {
    final a = _single(3, NestedKeyType.a);
    final b = _single(3, NestedKeyType.b);

    final split = splitKnownStatic([a, b], (n) => n == a ? known : null);

    expect(split.attack, [a, b]);
    expect(split.known, isEmpty);
  });

  test('sectors are decided independently', () {
    final known3a = _single(3, NestedKeyType.a);
    final known3b = _single(3, NestedKeyType.b);
    final unknown4 = _single(4, NestedKeyType.a);

    final split = splitKnownStatic([
      known3a,
      known3b,
      unknown4,
    ], (n) => n == unknown4 ? null : known);

    expect(split.attack, [unknown4]);
    expect(split.known.keys, [known3a, known3b]);
  });

  test('a lone key with no partner is still skipped when known', () {
    final only = _single(7, NestedKeyType.a);

    final split = splitKnownStatic([only], (_) => known);

    expect(split.attack, isEmpty);
    expect(split.known, {only: known});
  });

  // Key A and key B of one sector are two keys, not one. Without the B in
  // this case, dropping keyType from the dedupe key still passes - which it
  // did, and the cost downstream is severe: a key-blind dedupe drops one half
  // of every sector before the sector-at-a-time rule above ever sees it.
  test('the same sector key read twice is one key, but A and B are two', () {
    final a = _single(3, NestedKeyType.a);
    final b = _single(3, NestedKeyType.b);
    final aAgain = _single(3, NestedKeyType.a);

    expect(dedupeNestedNonces([a, b, aAgain]), hasLength(2));
  });

  test('the same sector on two cards is two keys', () {
    final one = _single(3, NestedKeyType.a);
    final other = _single(3, NestedKeyType.a, cuid: 0x11223344);

    expect(dedupeNestedNonces([one, other]), hasLength(2));
  });
}
